from pathlib import Path
import secrets

EXAMPLE_PATH = Path(".env.example")
OUTPUT_PATH = Path(".env")


def hex_secret(byte_count: int = 32) -> str:
    return secrets.token_hex(byte_count)


def password() -> str:
    return hex_secret(24)


if not EXAMPLE_PATH.exists():
    raise SystemExit(f"Example env file not found: {EXAMPLE_PATH}")

if OUTPUT_PATH.exists():
    raise SystemExit(f"Refusing to overwrite existing env file: {OUTPUT_PATH}")

content = EXAMPLE_PATH.read_text()
replacements = {
    "POSTGRES_ADMIN_PASSWORD=generated_by_scripts_New-Secrets_ps1": f"POSTGRES_ADMIN_PASSWORD={password()}",
    "NEWAPI_DB_PASSWORD=generated_by_scripts_New-Secrets_ps1": f"NEWAPI_DB_PASSWORD={password()}",
    "SUB2API_DB_PASSWORD=generated_by_scripts_New-Secrets_ps1": f"SUB2API_DB_PASSWORD={password()}",
    "REDIS_PASSWORD=generated_by_scripts_New-Secrets_ps1": f"REDIS_PASSWORD={password()}",
    "NEWAPI_SESSION_SECRET=generated_by_scripts_New-Secrets_ps1": f"NEWAPI_SESSION_SECRET={hex_secret(32)}",
    "NEWAPI_CRYPTO_SECRET=generated_by_scripts_New-Secrets_ps1": f"NEWAPI_CRYPTO_SECRET={hex_secret(32)}",
    "SUB2API_ADMIN_PASSWORD=generated_by_scripts_New-Secrets_ps1": f"SUB2API_ADMIN_PASSWORD={password()}",
    "SUB2API_JWT_SECRET=generated_by_scripts_New-Secrets_ps1": f"SUB2API_JWT_SECRET={hex_secret(32)}",
    "SUB2API_TOTP_ENCRYPTION_KEY=generated_by_scripts_New-Secrets_ps1": f"SUB2API_TOTP_ENCRYPTION_KEY={hex_secret(32)}",
}

for old, new in replacements.items():
    content = content.replace(old, new)

OUTPUT_PATH.write_text(content)
print(f"Wrote {OUTPUT_PATH}")
print("Store this file securely. It contains production secrets.")
