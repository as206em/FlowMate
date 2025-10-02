# Signing the app:
1. Create a Self-Signed Code Signing Certificate
- Open Keychain Access (Applications → Utilities → Keychain Access).
- From the menu: Keychain Access → Certificate Assistant → Create a Certificate.
- Fill in:
    - Name: Proofreader Dev Certificate (must match exactly what you’ll use in the script).
    - Identity Type: Self Signed Root.
    - Certificate Type: Code Signing.
    - Check Let me override defaults.
    - On the next screens, accept defaults until you see Key Usage, make sure Code Signing is included.
    - Finish, and the certificate will appear in login → Certificates in Keychain.
2. Trust the Certificate
- Double click the new certificate in Keychain.
- Expand Trust and set Code Signing → Always Trust.
- Close, enter your password if prompted.


# Progress:
- improve how data stored (drop all default values, save one obj, make it extendable to add new keys)
- test connection is not working on the settings page
- improve how connection is passed and provider factory