use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

use thiserror::Error;

pub const QTYPE_A: u16 = 1;
pub const QTYPE_AAAA: u16 = 28;
const QCLASS_IN: u16 = 1;
const DNS_HEADER_LEN: usize = 12;
const MAX_NAME_HOPS: usize = 10;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum DnsWireError {
    #[error("DNS name is empty")]
    EmptyName,
    #[error("DNS name label is too long")]
    LabelTooLong,
    #[error("DNS message is truncated")]
    Truncated,
    #[error("DNS message contains an invalid compression pointer")]
    BadPointer,
    #[error("DNS name is too long")]
    NameTooLong,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DnsRecord {
    pub address: IpAddr,
    pub ttl_secs: u32,
}

pub fn encode_query(id: u16, name: &str, qtype: u16) -> Result<Vec<u8>, DnsWireError> {
    let mut message = Vec::with_capacity(64);
    message.extend_from_slice(&id.to_be_bytes());
    message.extend_from_slice(&0x0100u16.to_be_bytes()); // RD
    message.extend_from_slice(&1u16.to_be_bytes()); // QDCOUNT
    message.extend_from_slice(&0u16.to_be_bytes()); // ANCOUNT
    message.extend_from_slice(&0u16.to_be_bytes()); // NSCOUNT
    message.extend_from_slice(&0u16.to_be_bytes()); // ARCOUNT
    encode_name(name, &mut message)?;
    message.extend_from_slice(&qtype.to_be_bytes());
    message.extend_from_slice(&QCLASS_IN.to_be_bytes());
    Ok(message)
}

pub fn decode_addresses(message: &[u8], qtype: u16) -> Result<Vec<DnsRecord>, DnsWireError> {
    if message.len() < DNS_HEADER_LEN {
        return Err(DnsWireError::Truncated);
    }
    let qdcount = u16::from_be_bytes([message[4], message[5]]) as usize;
    let ancount = u16::from_be_bytes([message[6], message[7]]) as usize;
    let mut offset = DNS_HEADER_LEN;
    for _ in 0..qdcount {
        skip_name(message, &mut offset)?;
        offset = offset
            .checked_add(4)
            .filter(|value| *value <= message.len())
            .ok_or(DnsWireError::Truncated)?;
    }

    let mut records = Vec::new();
    for _ in 0..ancount {
        skip_name(message, &mut offset)?;
        if offset + 10 > message.len() {
            return Err(DnsWireError::Truncated);
        }
        let rtype = u16::from_be_bytes([message[offset], message[offset + 1]]);
        let _rclass = u16::from_be_bytes([message[offset + 2], message[offset + 3]]);
        let ttl = u32::from_be_bytes([
            message[offset + 4],
            message[offset + 5],
            message[offset + 6],
            message[offset + 7],
        ]);
        let rdlength = u16::from_be_bytes([message[offset + 8], message[offset + 9]]) as usize;
        offset += 10;
        if offset + rdlength > message.len() {
            return Err(DnsWireError::Truncated);
        }
        let rdata = &message[offset..offset + rdlength];
        offset += rdlength;
        if rtype != qtype {
            continue;
        }
        match (qtype, rdlength) {
            (QTYPE_A, 4) => records.push(DnsRecord {
                address: IpAddr::V4(Ipv4Addr::new(rdata[0], rdata[1], rdata[2], rdata[3])),
                ttl_secs: ttl,
            }),
            (QTYPE_AAAA, 16) => {
                let mut octets = [0u8; 16];
                octets.copy_from_slice(rdata);
                records.push(DnsRecord {
                    address: IpAddr::V6(Ipv6Addr::from(octets)),
                    ttl_secs: ttl,
                });
            }
            _ => {}
        }
    }
    Ok(records)
}

fn encode_name(name: &str, out: &mut Vec<u8>) -> Result<(), DnsWireError> {
    let trimmed = name.trim().trim_end_matches('.');
    if trimmed.is_empty() {
        return Err(DnsWireError::EmptyName);
    }
    let start_len = out.len();
    for label in trimmed.split('.') {
        if label.is_empty() {
            return Err(DnsWireError::EmptyName);
        }
        if label.len() > 63 {
            return Err(DnsWireError::LabelTooLong);
        }
        out.push(label.len() as u8);
        out.extend_from_slice(label.as_bytes());
        if out.len() - start_len > 253 {
            return Err(DnsWireError::NameTooLong);
        }
    }
    out.push(0);
    Ok(())
}

fn skip_name(message: &[u8], offset: &mut usize) -> Result<(), DnsWireError> {
    let mut hops = 0;
    let mut jumped = false;
    let mut cursor = *offset;
    loop {
        if hops > MAX_NAME_HOPS {
            return Err(DnsWireError::BadPointer);
        }
        if cursor >= message.len() {
            return Err(DnsWireError::Truncated);
        }
        let len = message[cursor];
        if len & 0xC0 == 0xC0 {
            if cursor + 1 >= message.len() {
                return Err(DnsWireError::Truncated);
            }
            let pointer = (((len as usize) & 0x3F) << 8) | message[cursor + 1] as usize;
            if pointer >= message.len() {
                return Err(DnsWireError::BadPointer);
            }
            if !jumped {
                *offset = cursor + 2;
                jumped = true;
            }
            cursor = pointer;
            hops += 1;
            continue;
        }
        if len & 0xC0 != 0 {
            return Err(DnsWireError::BadPointer);
        }
        cursor += 1 + len as usize;
        if !jumped {
            *offset = cursor;
        }
        if len == 0 {
            if !jumped {
                *offset = cursor;
            }
            return Ok(());
        }
        hops += 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encode_query_linux_do_a() {
        let message = encode_query(0x1234, "linux.do", QTYPE_A).unwrap();
        assert_eq!(&message[0..2], &[0x12, 0x34]);
        assert_eq!(&message[4..6], &[0x00, 0x01]);
        assert_eq!(
            &message[12..],
            &[5, b'l', b'i', b'n', b'u', b'x', 2, b'd', b'o', 0, 0, 1, 0, 1]
        );
    }

    #[test]
    fn decode_a_record_with_compression() {
        // Query for example.com + one A answer that compresses the name.
        let mut message = encode_query(1, "example.com", QTYPE_A).unwrap();
        // ANCOUNT = 1
        message[7] = 1;
        message.extend_from_slice(&[
            0xC0, 0x0C, // pointer to offset 12 (example.com)
            0x00, 0x01, // A
            0x00, 0x01, // IN
            0x00, 0x00, 0x00, 60, // TTL 60
            0x00, 0x04, // RDLENGTH
            93, 184, 216, 34,
        ]);
        let records = decode_addresses(&message, QTYPE_A).unwrap();
        assert_eq!(records.len(), 1);
        assert_eq!(
            records[0].address,
            IpAddr::V4(Ipv4Addr::new(93, 184, 216, 34))
        );
        assert_eq!(records[0].ttl_secs, 60);
    }

    #[test]
    fn decode_aaaa_record() {
        let mut message = encode_query(7, "ipv6.example", QTYPE_AAAA).unwrap();
        message[7] = 1;
        let name_pointer_offset = 12u16;
        message.extend_from_slice(&[
            0xC0,
            name_pointer_offset as u8,
            0x00,
            0x1C,
            0x00,
            0x01,
            0x00,
            0x00,
            0x01,
            0x2C,
            0x00,
            0x10,
        ]);
        message.extend_from_slice(&[0u8; 15]);
        message.push(1);
        let records = decode_addresses(&message, QTYPE_AAAA).unwrap();
        assert_eq!(records.len(), 1);
        assert_eq!(records[0].ttl_secs, 300);
        assert_eq!(
            records[0].address,
            IpAddr::V6(Ipv6Addr::from([
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
            ]))
        );
    }

    #[test]
    fn encode_rejects_empty_name() {
        assert_eq!(
            encode_query(1, "", QTYPE_A).unwrap_err(),
            DnsWireError::EmptyName
        );
    }
}
