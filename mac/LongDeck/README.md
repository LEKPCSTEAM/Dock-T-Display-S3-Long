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

### Live widgets

`pages[].live[]` holds live widgets next to `keys`; it is optional. Each entry is flat: `id`, `type` (`stat`, `volume` or `clock`), `col`, `row`, `w`, `h`, plus `metric` and `style` for `stat`. Metrics: `cpu`, `ram`, `gpu`, `temp`, `net_down`, `net_up`, `disk_free`, `disk_io`, `battery`. Styles: `bar`, `number`, `sparkline`. Keys and live widgets share the 8x2 grid and a cap of 16 widgets per page. The first-run sample includes a `Mac` page with these widgets.

    {"id":"cpu","type":"stat","metric":"cpu","style":"sparkline","col":0,"row":0,"w":2,"h":1}

Temperature reads SMC key `TCMz` without root; values outside 10-130 °C are dropped. `battery` shows `--` on a Mac without a battery.

## Pairing

Choose "Pair with board…", pick the board, then type the 6-digit code shown on its screen. The key is stored in the login Keychain (service `dev.longdeck.LongDeck`).
