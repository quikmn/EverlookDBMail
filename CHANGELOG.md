# Changelog

## v0.1.0 (2026-11-22)
- First version. `/email` opens the settings (`/mail` too, when no other addon has it).
- Every mail is read as soon as the mailbox opens: sender, subject, money, C.O.D., expiry, attachments and the auction house invoice. Each inbox row gets a tag: AH sold, AH expired, AH cancelled, AH won, AH outbid, Player, Your alt, NPC, C.O.D. or Other.
- A summary beside the mailbox: how many mails of each kind, the money and items in them, and Open all.
- Open all takes money and items, the last mail first, a little at a time (the pause is a setting). It skips C.O.D. and Game Master mail, and unread mail from players unless you switch that on. When your bags are full it pauses and says so (Continue goes on); closing the mailbox stops it. Which kinds of mail it takes are settings.
- Shift-left-click on a mail takes all of that mail's money and items. A plain click opens it as always. C.O.D. mail is never taken this way.
- Sending: a list button beside To: with your recent recipients and your characters on this realm, names completed as you type, and the postage with what the mail costs you in all.
- With EverlookDB Auctions loaded, every mail goes to its income ledger: sales tick off "money waiting", items back tick off expired or cancelled auctions, and nothing is counted twice.
