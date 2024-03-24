# Installing Marzban-node in Docker-compose

## USE:
```
sudo bash -c "$(curl -sL https://raw.githubusercontent.com/bkeenke/mz-node/main/init.sh)" @ install
```
## After launch
### Upload your certificate to the server at `/var/lib/marzban-node/ssl_client_cert.pem`
- `nano /var/lib/marzban-node/ssl_client_cert.pem`
- Paste your certificate
- Ctrl+S
- Ctrl+X
