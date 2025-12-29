# How Cloudflare DNS and Tunnel Work with External Registrars

This explains the high-level flow when your domain is registered outside Cloudflare (for example, GoDaddy or Namecheap)
while Cloudflare Tunnel handles DNS and inbound traffic.

## High-level flow

1) A domain is registered at an external registrar (for example, GoDaddy or Namecheap).
2) The domain is added as a Zone in Cloudflare.
3) Nameservers at the registrar are updated to point to Cloudflare.
4) Subdomains are created and managed in Cloudflare DNS.
5) Cloudflare Tunnel maps those subdomains to services on localhost.
6) Cloudflare proxies traffic to the tunnel so no inbound ports are open on your machine.

## Important notes / gotchas

- A public IP is not required.
- Port forwarding is not required.
- Firewall rules are not required for inbound traffic.
- After the nameserver switch, registrar DNS records are not used.
- The orange-cloud proxy must be enabled for tunnel-managed subdomains.
- Subdomains should not point to a public IP when using the tunnel.
- All inbound traffic flows through the tunnel.

## TLS / SSL behavior

Cloudflare typically auto-provisions TLS certificates for proxied hostnames. Full or Full (Strict) SSL mode is
recommended in most cases. Local services can remain HTTP because TLS terminates at Cloudflare before traffic is
proxied through the tunnel.

## TL;DR

- External registrars work fine in most cases once nameservers point to Cloudflare.
- Cloudflare manages DNS and SSL for the zone and subdomains.
- Cloudflare Tunnel securely proxies traffic to localhost.
- This setup is well-suited for homelab SaaS, demos, and early users.
