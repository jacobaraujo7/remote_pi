use std::net::{IpAddr, SocketAddr};

use anyhow::{bail, Context};

pub const DEFAULT_RELAY_BIND_ADDR: &str = "0.0.0.0";
pub const DEFAULT_RELAY_PORT: u16 = 3000;

pub fn relay_socket_addr_from_env() -> anyhow::Result<SocketAddr> {
    relay_socket_addr(
        std::env::var("REMOTEPI_RELAY_BIND_ADDR").ok().as_deref(),
        std::env::var("REMOTEPI_RELAY_PORT").ok().as_deref(),
    )
}

pub fn relay_socket_addr(
    bind_addr: Option<&str>,
    port: Option<&str>,
) -> anyhow::Result<SocketAddr> {
    let bind_addr = bind_addr.unwrap_or(DEFAULT_RELAY_BIND_ADDR);
    let ip: IpAddr = bind_addr
        .parse()
        .with_context(|| format!("invalid REMOTEPI_RELAY_BIND_ADDR {bind_addr:?}"))?;

    let port = match port {
        Some(raw) => raw
            .parse::<u16>()
            .with_context(|| format!("invalid REMOTEPI_RELAY_PORT {raw:?}"))?,
        None => DEFAULT_RELAY_PORT,
    };

    if port == 0 {
        bail!("REMOTEPI_RELAY_PORT must be between 1 and 65535");
    }

    Ok(SocketAddr::new(ip, port))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_to_existing_public_bind() {
        assert_eq!(
            relay_socket_addr(None, None).unwrap(),
            SocketAddr::from(([0, 0, 0, 0], DEFAULT_RELAY_PORT)),
        );
    }

    #[test]
    fn parses_loopback_bind_address() {
        assert_eq!(
            relay_socket_addr(Some("127.0.0.1"), Some("8080")).unwrap(),
            SocketAddr::from(([127, 0, 0, 1], 8080)),
        );
    }

    #[test]
    fn parses_tailscale_style_bind_address() {
        assert_eq!(
            relay_socket_addr(Some("100.64.12.34"), Some("3000")).unwrap(),
            SocketAddr::from(([100, 64, 12, 34], 3000)),
        );
    }

    #[test]
    fn parses_ipv6_bind_address() {
        assert_eq!(
            relay_socket_addr(Some("::1"), Some("3000")).unwrap(),
            SocketAddr::new("::1".parse().unwrap(), 3000),
        );
    }

    #[test]
    fn rejects_invalid_bind_address() {
        let err = relay_socket_addr(Some("not an ip"), Some("3000")).unwrap_err();
        assert!(err.to_string().contains("invalid REMOTEPI_RELAY_BIND_ADDR"));
    }

    #[test]
    fn rejects_invalid_port() {
        let err = relay_socket_addr(Some("127.0.0.1"), Some("99999")).unwrap_err();
        assert!(err.to_string().contains("invalid REMOTEPI_RELAY_PORT"));
    }

    #[test]
    fn rejects_zero_port() {
        let err = relay_socket_addr(Some("127.0.0.1"), Some("0")).unwrap_err();
        assert!(err
            .to_string()
            .contains("REMOTEPI_RELAY_PORT must be between 1 and 65535"));
    }
}
