use crate::api::Packet;
use prost::Message;
use std::io::{Read, Write};
use std::net::TcpStream;

const MAX_PACKET_LENGTH: usize = 16 * 1024 * 1024;

pub struct NetworkClient {
    pub stream: TcpStream,
}

impl NetworkClient {
    pub fn connect(address: &str) -> Result<Self, std::io::Error> {
        let stream = TcpStream::connect(address)?;
        Ok(Self { stream })
    }

    pub fn try_clone_stream(&self) -> Result<TcpStream, std::io::Error> {
        self.stream.try_clone()
    }

    pub fn receive_packet(&mut self) -> Result<Packet, std::io::Error> {
        let mut len_buf = [0u8; 4];
        self.stream.read_exact(&mut len_buf)?;

        let length = u32::from_le_bytes(len_buf) as usize;
        if length > MAX_PACKET_LENGTH {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("packet length {length} exceeds max {MAX_PACKET_LENGTH}"),
            ));
        }

        let mut data_buf = vec![0u8; length];
        self.stream.read_exact(&mut data_buf)?;

        let packet = Packet::decode(&data_buf[..])
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;

        Ok(packet)
    }

    pub fn send_packet(&mut self, packet: &Packet) -> Result<(), std::io::Error> {
        let mut data = Vec::new();
        packet
            .encode(&mut data)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
        if data.len() > MAX_PACKET_LENGTH {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!(
                    "packet length {} exceeds max {MAX_PACKET_LENGTH}",
                    data.len()
                ),
            ));
        }

        let len_buf = (data.len() as u32).to_le_bytes();
        self.stream.write_all(&len_buf)?;
        self.stream.write_all(&data)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::ErrorKind;
    use std::net::TcpListener;
    use std::thread;

    fn connected_clients() -> (NetworkClient, NetworkClient) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();

        let accept_thread = thread::spawn(move || {
            let (stream, _) = listener.accept().unwrap();
            NetworkClient { stream }
        });

        let client = NetworkClient::connect(&address.to_string()).unwrap();
        let server = accept_thread.join().unwrap();
        (client, server)
    }

    #[test]
    fn send_and_receive_empty_packet() {
        let (mut sender, mut receiver) = connected_clients();
        let packet = Packet { payload: None };

        sender.send_packet(&packet).unwrap();
        let received = receiver.receive_packet().unwrap();

        assert!(received.payload.is_none());
    }

    #[test]
    fn receive_rejects_oversized_packet_length() {
        let (mut sender, mut receiver) = connected_clients();
        sender
            .stream
            .write_all(&((MAX_PACKET_LENGTH as u32) + 1).to_le_bytes())
            .unwrap();

        let err = receiver.receive_packet().unwrap_err();

        assert_eq!(err.kind(), ErrorKind::InvalidData);
    }
}
