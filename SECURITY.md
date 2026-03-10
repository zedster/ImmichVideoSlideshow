# Security Policy

## Reporting a Vulnerability

Please do not open public issues for security vulnerabilities.
Report issues privately to the project maintainers.

When reporting, include:

- Affected component (`tvos-app` or `web-player`)
- Reproduction steps
- Impact assessment
- Suggested mitigation (if known)

## Deployment Hardening (Web Player)

- Run behind a reverse proxy and restrict access to trusted networks when possible.
- Keep `DEBUG=false` in production.
- Use HTTPS between clients and your deployment.
- Set `MUTATION_TOKEN` to protect mutation endpoints (`watch.php`, `favorite.php`).
- Keep Immich API credentials in environment variables only.

## Scope

This policy applies to the latest code on the default branch.