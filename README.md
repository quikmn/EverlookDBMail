# EverlookDB Mail

WoW Forever (interface 16001). A simple mailbox helper: Open all, shift-click a mail to take all of it, a tag on every mail saying what it is, the inbox's totals, and your recent recipients and alts when you send. `/email` opens the settings (`/mail` too, when no other addon uses it).

## At the mailbox

- **Tags:** every mail is read as soon as the mailbox opens (sender, subject, money, C.O.D., expiry, attachments and the auction house invoice, without opening the mail) and each inbox row says what it is: **AH sold**, **AH expired**, **AH cancelled**, **AH won**, **AH outbid**, **Player**, **Your alt**, **NPC**, **C.O.D.** or **Other**.
- **Summary:** a panel beside the mailbox with how many mails of each kind, the money and items in them, what Open all will take, and the **Open all** button. Drag it where you like; the gear opens the settings.
- **Open all** takes the money and items of your mail, the last mail first, one thing at a time (it waits for the server, then a short pause you can set). It never takes C.O.D. or Game Master mail, and leaves unread mail from players alone unless you switch that on, so you don't miss a letter. Which kinds it takes (auction house, your alts, NPCs, players) are settings. When your bags are full it pauses and says so: make room and click **Continue**. Closing the mailbox stops it at once.
- **Shift-left-click** on a mail takes all of that mail's money and items. A plain click opens the mail as always. C.O.D. mail is never taken this way: open it to pay.
- More than 50 mails: Open all says how many are still on the server and asks for them when it is done.

## Sending

- A list button beside **To:** with your recent recipients (newest first) and your characters on this realm (each one is added when it logs in). Click a name to fill **To:**.
- Names complete as you type, from those two lists.
- Beside it: the postage, and what the mail costs you in all when you send gold.
- No bulk sending.

`/email forget <name>` takes a name off both lists.

## With EverlookDB Auctions

When EverlookDB Auctions is loaded, Mail hands it every mail it reads and every take, through Auctions' API (`EverlookDBAuctionsAPI.mail`, version 4). Its income ledger then ticks off auctions: a sale's money taken, an expired or cancelled auction's item back. Gold from your alts is a transfer there, not income. Auctions reads the mail itself too; each mail counts once. Each addon works on its own.

Both carry the same mail classifier (`MailClassify.lua`, LibStub `EverlookMailClassify-1`); when both are loaded the newest copy is used.

## For other addons

`EverlookDBMailAPI` (read-only):

- `version` (1)
- `isAlt(name)`: true for your own characters on this realm
- `alts()`: their names
- `lastScan()`: the inbox as last read (copies): `{ index, sender, subject, money, cod, exp, items = { { slot, name, id, count, link } }, invoice, cat, item, count }`
- `categories`: `{ ids = { "ah_sold", ... }, labels = { ah_sold = "AH sold", ... } }`

## Chat commands

- `/email`: the settings. `/email help` lists the commands.
- `/email open`: Open all now (at a mailbox). `/email stop`: stop it.
- `/email alts`: your characters on this realm. `/email forget <name>`.
- `/email <setting> <value>`, `/email get`, `/email status`, `/email version`, as in every EverlookDB addon.

## Saved data

`EverlookMailDB`: your settings, the recent recipients you sent mail to, and your characters' names, class and level per realm. Nothing is uploaded.

## Clean room

Postal (the classic mail addon) is "All Rights Reserved", so none of its code was read or used. EverlookDB Mail is written from the game's own mail API and Blizzard's mail frame.

## Tests

`python -P tests/run.py` (Lua 5.1 through lupa, with `tests/wowmock.lua`).

## Licence

GPL-3.0 (see LICENSE).
