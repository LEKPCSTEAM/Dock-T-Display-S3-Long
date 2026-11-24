# LongDeck

Menu-bar app that pairs with the deck board over Bonjour (`_longdeck._tcp`), pushes key layouts and faces, and runs actions on the Mac when keys are pressed.

## Build

    cd mac/LongDeck
    swift test
    ./scripts/bundle.sh
    open build/LongDeck.app

`bundle.sh` signs ad-hoc by default. Set `LONGDECK_SIGN_ID` to use a named identity.

## Keep the Accessibility grant across rebuilds

Ad-hoc signatures change on every build, so macOS forgets the Accessibility grant. Sign with a stable self-signed certificate instead:

1. Open Keychain Access, then Certificate Assistant, then Create a Certificate.
2. Name it `LongDeck Dev`, set Identity Type to Self Signed Root and Certificate Type to Code Signing, then create it.
3. Build with `LONGDECK_SIGN_ID="LongDeck Dev" ./scripts/bundle.sh`.
4. Choose "Grant Accessibility…" in the menu and enable LongDeck once.

## Config

`~/Library/Application Support/LongDeck/config.json`. Changes are picked up automatically. An invalid file is not pushed and the error shows in the menu. Use "Open config folder" to create a sample.

## Pairing

Choose "Pair with board…", pick the board, then type the 6-digit code shown on its screen. The key is stored in the login Keychain (service `dev.longdeck.LongDeck`).
