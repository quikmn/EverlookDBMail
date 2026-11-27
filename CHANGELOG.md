# Changelog

## Unreleased
- Small fixes to the settings window: whichever window you click now comes to the front, and the settings list follows your search.

## v0.3.2 (2026-11-26)
- Settings: the gold total's switch says where the total now sits (above the money boxes).

## v0.3.1 (2026-11-26)
- Send Mail: the gold total now sits on the "Amount to send" line above the money boxes, so it no longer runs into the Postage line and the Subject box.

## v0.3.0 (2026-11-24)
- `/email alts` and the settings window show each alt's gold (with what waits in its mail) when EverlookDB Auctions is installed.

## v0.2.0 (2026-11-22)
- Everything now sits inside the game's mailbox: no more panel beside it.
- A tick box on every mail, with Select (all, none, auction house, sold, items back, alts, NPC, players...), Open selected and Return selected at the top of the inbox. Shift-click a tick box to tick a range, Ctrl-click for every mail from that sender.
- Shift-click a mail takes everything in it, reliably now, and several in a row all get taken.
- Ctrl-click a mail returns it to the sender (mail from players only).
- The mail tags are smaller and sit next to the subject.
- Open all sits where the game's button is. Shift-click it to take every mail whatever the settings say; right-click it for the settings. With full bags it still takes the gold, then goes on by itself when you make room. It says what it left behind, and goes on when more mail arrives.
- One chat line when you close the mailbox: the gold you took.
- Sending: Tab in To: takes the suggested name. Names also come from your friends and guild. The list sits on a small arrow next to To:, the total cost sits under the postage, and gold you send with an empty subject becomes the subject.
- If another mail addon already does these things, EverlookDB Mail leaves them to it and says so once.

## v0.1.0 (2026-11-22)
- First version. `/email` opens the settings (`/mail` too, when no other addon has it).
- Every mail is read as soon as the mailbox opens: sender, subject, money, C.O.D., expiry, attachments and the auction house invoice. Each inbox row gets a tag: AH sold, AH expired, AH cancelled, AH won, AH outbid, Player, Your alt, NPC, C.O.D. or Other.
- A summary beside the mailbox: how many mails of each kind, the money and items in them, and Open all.
- Open all takes money and items, the last mail first, a little at a time (the pause is a setting). It skips C.O.D. and Game Master mail, and unread mail from players unless you switch that on. When your bags are full it pauses and says so (Continue goes on); closing the mailbox stops it. Which kinds of mail it takes are settings.
- Shift-left-click on a mail takes all of that mail's money and items. A plain click opens it as always. C.O.D. mail is never taken this way.
- Sending: a list button beside To: with your recent recipients and your characters on this realm, names completed as you type, and the postage with what the mail costs you in all.
- With EverlookDB Auctions loaded, every mail goes to its income ledger: sales tick off "money waiting", items back tick off expired or cancelled auctions, and nothing is counted twice.
