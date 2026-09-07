# Dual IPA authorized signing service

This service is designed for certificates and provisioning profiles that the operator is authorized to use. Keep P12 files, passwords, and private keys on the signing Mac/server; never commit them to Git.

## Requirements

- macOS with Xcode command-line tools
- Python 3.11+
- An HTTPS reverse proxy in production
- One directory per authorized certificate containing the matching `.p12` and `.mobileprovision`

Example layout:

```text
signing-service/
  server.py
  requirements.txt
  certs/
    Example/
      signing.p12
      profile.mobileprovision
```

Set `CERTS_ROOT` to the certificates directory and `P12_PASSWORD_<ALIAS>` environment variables for passwords. Do not put passwords in source control.

The app sends `certificate` and `ipa` fields to `POST /sign`. The response is JSON containing `installManifestURL`.

This repository does not contain or request the third-party private keys from public certificate archives.
