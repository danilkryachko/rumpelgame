use std::io::{Read, Write};
use std::net::TcpStream;
use prost::Message;
use crate::api::api::{Packet, packet::Payload};

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
        let mut data_buf = vec![0u8; length];
        self.stream.read_exact(&mut data_buf)?;
        
        let packet = Packet::decode(&data_buf[..])
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
            
        Ok(packet)
    }

    pub fn send_packet(&mut self, packet: &Packet) -> Result<(), std::io::Error> {
        use prost::Message;
        let mut data = Vec::new();
        packet.encode(&mut data)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;

        let len_buf = (data.len() as u32).to_le_bytes();
        self.stream.write_all(&len_buf)?;
        self.stream.write_all(&data)?;
        Ok(())
    }
}
