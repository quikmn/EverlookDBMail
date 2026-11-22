# EverlookDB Mail

A simple mailbox helper for WoW Forever, built into the game's own mailbox: tick mails and open or return them, Open all, Shift-click a mail to take everything in it, a small tag on every mail saying what it is, and Tab completes names when you send. `/email` opens the settings (`/mail` too, when no other addon uses it).

## At the mailbox

- **Tags:** every mail is read as soon as the mailbox opens (without opening it) and gets a short coloured tag next to its subject: **AH sold**, **AH expired**, **AH cancelled**, **AH won**, **AH outbid**, **Player**, **Your alt**, **NPC** or **C.O.D.**
- **Tick boxes:** a tick box on the left of every mail. At the top of the inbox: **Select** (all, none, auction house, sold, items back, won, your alts, NPC, players, with gold, with items), **Open selected** (takes the gold and items) and **Return selected** (sends them back). On a tick box, Shift-click ticks every mail from the last one you ticked, and Ctrl-click every mail from the same sender.
- **Shift-click** a mail: takes all of its gold and items, without opening it. Click a few in a row and they are all taken. C.O.D. mail is never taken this way: open it to pay.
- **Ctrl-click** a mail: returns it to the sender. Only mail from players can go back.
- **Open all** (where the game's button is) takes the gold and items of your mail, the last mail first, a little at a time. It never takes C.O.D. or Game Master mail, and leaves unread mail from players alone unless you switch that on, so you don't miss a letter. Which kinds it takes are settings (right-click the button); Shift-click it to take every mail anyway. When your bags are full it still takes the gold, then pauses and goes on when you make room. Closing the mailbox stops it at once. When it's done it says what it took and what it left.
- More than 50 mails: Open all asks for the rest and goes on when they arrive.
- When you close the mailbox, one chat line says how much gold you took.
- A plain click opens a mail as always.

## Sending

- **Tab** in **To:** takes the suggested name. With nothing to complete, Tab moves on as usual.
- Names complete as you type, from your recent recipients, your characters on this realm, your friends and your guild.
- A small arrow next to **To:** lists them all (recent first). Click a name to fill **To:**.
- Under the postage: what the mail costs you in all when you send gold.
- Send gold with an empty subject and the subject becomes the amount ("5g 20s").
- No bulk sending.

`/email forget <name>` takes a name off your recent recipients and alts.

If you use another mail addon that already does these things, EverlookDB Mail leaves its buttons and clicks to it (it says so once in chat) and keeps the tags.

## With EverlookDB Auctions

When EverlookDB Auctions is loaded, its income ledger ticks off your auctions as you take your mail: a sale's money taken, an expired or cancelled auction's item back. Gold from your alts counts as a transfer, not income, and nothing is counted twice. Each addon also works on its own.

## Chat commands

- `/email`: the settings. `/email help` lists the commands.
- `/email open`: Open all now (at a mailbox). `/email stop`: stop it.
- `/email alts`: your characters on this realm. `/email forget <name>`.
- `/email <setting> <value>`, `/email get`, `/email status`, `/email version`, as in every EverlookDB addon.

## Your data

Your settings, recent recipients and your characters' names stay on your computer. Nothing is uploaded.

## Licence

GPL-3.0 (see LICENSE).
