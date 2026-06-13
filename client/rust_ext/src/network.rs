use crate::api::Packet;
use prost::Message;
use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::Instant;

const MAX_PACKET_LENGTH: usize = 16 * 1024 * 1024;

pub struct NetworkClient {
    pub stream: TcpStream,
}

pub struct PacketReadTiming {
    pub read_ms: f64,
    pub decode_ms: f64,
    pub reader_elapsed_ms: f64,
    pub queue_lag_ms: f64,
}

pub struct PacketReadRecord {
    pub packet: Packet,
    pub timing: PacketReadTiming,
    pub received_at: Instant,
}

impl NetworkClient {
    pub fn connect(address: &str) -> Result<Self, std::io::Error> {
        let stream = TcpStream::connect(address)?;
        Ok(Self { stream })
    }

    pub fn try_clone_stream(&self) -> Result<TcpStream, std::io::Error> {
        self.stream.try_clone()
    }

    #[allow(dead_code)]
    pub fn receive_packet(&mut self) -> Result<Packet, std::io::Error> {
        self.receive_packet_with_timing()
            .map(|record| record.packet)
    }

    pub fn receive_packet_with_timing(&mut self) -> Result<PacketReadRecord, std::io::Error> {
        self.receive_packet_with_timing_since(Instant::now())
    }

    pub fn receive_packet_with_timing_since(
        &mut self,
        reader_start: Instant,
    ) -> Result<PacketReadRecord, std::io::Error> {
        let read_start = Instant::now();
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
        let read_ms = read_start.elapsed().as_secs_f64() * 1000.0;

        let decode_start = Instant::now();
        let packet = Packet::decode(&data_buf[..])
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
        let decode_ms = decode_start.elapsed().as_secs_f64() * 1000.0;
        let received_at = Instant::now();
        let reader_elapsed_ms = reader_start.elapsed().as_secs_f64() * 1000.0;

        Ok(PacketReadRecord {
            packet,
            timing: PacketReadTiming {
                read_ms,
                decode_ms,
                reader_elapsed_ms,
                queue_lag_ms: 0.0,
            },
            received_at,
        })
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
