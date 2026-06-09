use std::io::Read;
use std::net::TcpStream;
use prost::Message;
use crate::api::api::{Packet, packet::Payload};

pub struct NetworkClient {
    stream: TcpStream,
}

impl NetworkClient {
    pub fn connect(address: &str) -> Result<Self, std::io::Error> {
        let stream = TcpStream::connect(address)?;
        Ok(Self { stream })
    }

    pub fn receive_packet(&mut self) -> Result<Packet, Box<dyn std::error::Error>> {
        let mut len_buf = [0u8; 4];
        self.stream.read_exact(&mut len_buf)?;
        let length = u32::from_le_bytes(len_buf) as usize;

        let mut data_buf = vec![0u8; length];
        self.stream.read_exact(&mut data_buf)?;

        let packet = Packet::decode(&data_buf[..])?;
        Ok(packet)
    }
}
