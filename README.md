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
- refactor:
    - move config classes into sperate files
    - improve project strcture 
    - move views into seprate folder
    - move services into folders and helper
- check if i can delete copy-icon
- rename app into flow mate
- update dropdown menu and remove sleected model
- think about the test connection work

