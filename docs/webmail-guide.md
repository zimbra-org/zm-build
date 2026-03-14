# CXS Webmail User Guide

Access: **https://mail.cloudxspace.com**

Login with your email address and password.

---

## Overview

CXS Webmail is a full-featured email client accessible from any web browser. It provides:
- Email (compose, read, organize)
- Contacts / Address Book
- Search
- Preferences & Settings
- Mail Filters

Features **not available** in this build: Calendar, Tasks, Briefcase, Documents, Chat, Spell Check.

---

## 1. Mail

### 1.1 Reading Email

After login, you land in the **Inbox**.

**Views available** (toggle via View menu):
- **Conversation view**: Groups related messages together by subject (default)
- **Message list view**: Shows each message individually

**Reading pane positions** (change in Preferences > Mail):
- Right side (vertical split)
- Bottom (horizontal split)
- Off (click to open in full view)

**Message indicators:**
| Icon/Flag | Meaning |
|-----------|---------|
| Bold text | Unread message |
| Paperclip | Has attachment(s) |
| Star/Flag | Flagged/important |
| Arrow | Replied or forwarded |
| Color tag | Tagged with a category |

### 1.2 Composing Email

Click **New Message** button or press `C`.

**Compose features:**
- **To / Cc / Bcc**: Type addresses (autocomplete from contacts and GAL)
- **Subject**: Message subject line
- **Body**: Rich text (HTML) or plain text editor
- **Formatting toolbar**: Bold, italic, underline, lists, colors, fonts
- **Attachments**: Click the paperclip or drag & drop files
- **Priority**: Set high/normal/low priority
- **Request read receipt**: Ask recipient to confirm reading
- **Signatures**: Automatically appended (configurable in Preferences)

**Compose shortcuts:**
| Shortcut | Action |
|----------|--------|
| `C` | New message |
| `R` | Reply |
| `A` | Reply All |
| `F` | Forward |
| `Ctrl+Enter` | Send |

### 1.3 Reply, Forward, Redirect

- **Reply**: Responds to sender only
- **Reply All**: Responds to sender and all recipients
- **Forward**: Sends the message to someone else (as inline or attachment)
- **Redirect**: Sends the original message as-is (preserving original sender)

### 1.4 Attachments

- **Attach files**: Click paperclip icon or drag files into compose window
- **Attach from email**: Forward attachments from other messages
- **Download**: Click attachment name to download
- **Preview**: Some file types (images, PDFs) can be previewed inline
- **Remove**: Click X on attachment before sending

### 1.5 Folders

**Default folders:**
| Folder | Purpose |
|--------|---------|
| Inbox | Incoming mail |
| Drafts | Unsent messages (auto-saved every 15 seconds) |
| Sent | Copies of messages you sent |
| Trash | Deleted messages (auto-purged based on policy) |
| Junk | Spam messages (auto-purged based on policy) |

**Custom folders:**
- Right-click Folders > **New Folder**
- Drag & drop messages into folders
- Create nested sub-folders
- Set folder colors for visual organization

**Folder actions** (right-click a folder):
- Rename, Move, Delete
- Mark all as read
- Empty folder (for Trash/Junk)
- Share folder with other users
- Edit properties (color, retention)

### 1.6 Tags

Tags are labels you can apply to messages for organization. Unlike folders, a message can have multiple tags.

- **Create tag**: Right-click Tags in left panel > New Tag
- **Apply tag**: Right-click a message > Tag > select tag
- **Tag colors**: Each tag can have a different color
- **Filter by tag**: Click a tag name to show all messages with that tag

### 1.7 Flags / Stars

Click the star icon next to a message to flag it. Flagged messages can be found by searching `is:flagged`.

### 1.8 Drag & Drop

- Drag messages to folders to move them
- Drag messages to tags to tag them
- Drag messages to Trash to delete
- Drag files into compose window to attach

---

## 2. Search

### 2.1 Quick Search

Type in the search bar at the top and press Enter. Searches message content, subject, sender, and recipients by default.

### 2.2 Search Operators

Use these in the search bar for precise results:

| Operator | Example | What it finds |
|----------|---------|---------------|
| `from:` | `from:john` | Messages from John |
| `to:` | `to:support` | Messages sent to support |
| `cc:` | `cc:boss` | Messages where boss is CC'd |
| `subject:` | `subject:invoice` | Subject contains "invoice" |
| `in:` | `in:sent` | Messages in Sent folder |
| `has:attachment` | `has:attachment` | Messages with attachments |
| `is:unread` | `is:unread` | Unread messages |
| `is:flagged` | `is:flagged` | Starred/flagged messages |
| `is:read` | `is:read` | Read messages |
| `date:` | `date:last-week` | Messages from last week |
| `before:` | `before:3/1/2026` | Messages before a date |
| `after:` | `after:1/1/2026` | Messages after a date |
| `larger:` | `larger:5mb` | Messages larger than 5MB |
| `smaller:` | `smaller:100kb` | Messages smaller than 100KB |
| `tag:` | `tag:important` | Messages with specific tag |
| `content:` | `content:password` | Body contains "password" |

**Combine operators:**
```
from:john has:attachment after:1/1/2026
```

### 2.3 Saved Searches

1. Perform a search
2. Click **Save** in the search toolbar
3. Name your saved search
4. It appears in the left panel under Searches

---

## 3. Contacts / Address Book

### 3.1 Viewing Contacts

Click the **Contacts** tab in the left panel (or the app switcher).

**Address books:**
- **Contacts**: Your personal contacts
- **Emailed Contacts**: Auto-added from people you email
- **Global Address List (GAL)**: Company directory (all accounts on the server)

### 3.2 Creating a Contact

1. Click **New Contact**
2. Fill in fields:
   - Name (first, last, display)
   - Email (can add multiple)
   - Phone (work, mobile, home)
   - Address
   - Company, title, department
   - Notes
   - Photo
3. Click **Save**

### 3.3 Contact Groups

Contact groups let you email multiple people at once.

1. Click **New Contact Group**
2. Name the group
3. Add members (search or type addresses)
4. Click **Save**
5. When composing, type the group name in To/Cc/Bcc

### 3.4 Import / Export Contacts

**Import:**
1. Go to Preferences > Contacts (or right-click address book)
2. Click **Import**
3. Select a CSV file
4. Choose destination address book

**Export:**
1. Right-click an address book
2. Click **Export**
3. Downloads as CSV

### 3.5 Autocomplete

When composing, start typing a name or email. Suggestions appear from:
1. Your personal contacts
2. Emailed contacts (people you've written to before)
3. GAL (company directory)

---

## 4. Mail Filters

### 4.1 What Are Filters?

Filters automatically process incoming messages based on rules you define. Example: "Move all messages from boss@company.com to the Important folder."

### 4.2 Creating a Filter

**Path:** Preferences > Filters > **New Filter**

Each filter has:
- **Name**: A label for the filter
- **Conditions**: When to apply (match any or all)
  - From, To, Cc, Subject, Body, Header, Size, Date, Attachment
  - Contains, matches exactly, doesn't contain, matches wildcard
- **Actions**: What to do
  - Move to folder
  - Tag with
  - Mark as read
  - Mark as flagged
  - Forward to address
  - Discard (delete)
  - Keep in Inbox

### 4.3 Filter Examples

**Move newsletters to a folder:**
- Condition: From contains `newsletter`
- Action: Move to folder "Newsletters"

**Flag emails from boss:**
- Condition: From is `boss@cloudxspace.com`
- Action: Mark as flagged

**Delete large attachments:**
- Condition: Size is larger than 25MB
- Action: Discard

### 4.4 Filter Order

Filters are processed top-to-bottom. Drag to reorder. A message stops processing at the first matching filter (unless the filter explicitly continues).

---

## 5. Preferences / Settings

**Path:** Click the gear icon or go to **Preferences** tab.

### 5.1 General

- **Language**: UI language
- **Time zone**: For timestamps
- **Default app**: What to show after login (Mail, Contacts)
- **Theme/Skin**: Visual appearance

### 5.2 Mail

**Displaying Messages:**
- Reading pane position (right, bottom, off)
- Show message snippets in list
- Mark as read delay (immediately, after 1/5/10 seconds)
- Display images from external sources

**Composing Messages:**
- Default compose format (HTML or plain text)
- Default font, size, color
- Auto-save drafts interval
- Always Bcc (send a copy to another address)

**Notifications:**
- Play a sound for new mail
- Flash browser tab for new mail
- Show desktop notification
- Forward new mail notification to another email

### 5.3 Accounts

Manage your email accounts and identities:

**Primary Account:**
- Display name
- Reply-to address
- Default signature

**Personas (Send-As Identities):**
- Create alternate "from" identities
- Each can have its own display name, reply-to, and signature
- Useful if you handle multiple roles

**External Accounts (POP/IMAP):**
- Add external email accounts to check from CXS webmail
- Configure server, port, SSL, username, password
- Choose where to deliver (Inbox or custom folder)

### 5.4 Signatures

1. Go to Preferences > Signatures
2. Click **New Signature**
3. Enter a name and compose your signature (HTML or plain text)
4. Go to the **Accounts** section to assign which signature to use for each identity
5. Options:
   - Use for new messages
   - Use for replies/forwards
   - Place above or below quoted text

### 5.5 Out of Office / Vacation Reply

**Path:** Preferences > Mail > Out of Office

1. Check **Send auto-reply message**
2. Write your away message
3. Optionally set date range (start/end date)
4. Optionally set a different reply for external senders
5. Click **Save**

The system sends one auto-reply per sender during the vacation period (not one per email).

### 5.6 Mail Forwarding

**Path:** Preferences > Mail > Receiving Messages

- Enter a forwarding address
- Choose whether to keep a local copy

### 5.7 Keyboard Shortcuts

**Path:** Preferences > Shortcuts (or press `?` anywhere)

**Essential shortcuts:**

| Shortcut | Action |
|----------|--------|
| `C` | Compose new message |
| `R` | Reply |
| `A` | Reply all |
| `F` | Forward |
| `Ctrl+Enter` | Send message |
| `Delete` | Move to trash |
| `Shift+Delete` | Permanently delete |
| `.` (period) | Mark read/unread |
| `S` | Star/flag |
| `T` | Tag |
| `M` | Move to folder |
| `V` | Move to folder (same as M) |
| `/` | Focus search bar |
| `?` | Show all shortcuts |
| `J` / `K` | Next / Previous message |
| `N` / `P` | Next / Previous conversation |
| `Ctrl+A` | Select all |

### 5.8 Trusted Senders

**Path:** Preferences > Trusted Addresses

Add email addresses or domains that should always display images and not be flagged as spam.

---

## 6. Sharing

### 6.1 Share a Mail Folder

1. Right-click a folder > **Share Folder**
2. Choose who to share with:
   - **Internal user**: Another account on this server
   - **External guest**: Someone outside (they get a link)
   - **Public**: Anyone with the URL
3. Set permission:
   - **Viewer**: Can read messages
   - **Manager**: Can read, edit, delete, and add messages
   - **Admin**: Full control including sub-shares
4. Click **OK**

The recipient gets an email invitation to accept the share.

### 6.2 Access a Shared Folder

When someone shares a folder with you:
1. You receive an email notification
2. Click **Accept Share** in the email
3. The shared folder appears in your folder tree
4. Or manually: right-click Folders > **Find Shares**

### 6.3 Delegate Access

Full delegation allows someone else to send email on your behalf:
1. Preferences > Accounts > **Add Delegate**
2. Select the user
3. Choose permissions: Send As, Send on Behalf Of

---

## 7. Mobile Access

### 7.1 IMAP/POP Access

Configure any email client (Outlook, Thunderbird, Apple Mail, mobile) with:

| Setting | Value |
|---------|-------|
| **IMAP Server** | mail.cloudxspace.com |
| **IMAP Port** | 993 (SSL) |
| **POP3 Server** | mail.cloudxspace.com |
| **POP3 Port** | 995 (SSL) |
| **SMTP Server** | mail.cloudxspace.com |
| **SMTP Port** | 465 (SSL) or 587 (STARTTLS) |
| **Username** | Full email address |
| **Authentication** | Normal password |
| **Encryption** | SSL/TLS |

### 7.2 ActiveSync (Mobile Devices)

For iPhone, Android, and other ActiveSync-compatible devices:
1. Go to device Settings > Accounts > Add Account > Exchange
2. Enter your email, password
3. Server: `mail.cloudxspace.com`
4. This syncs mail and contacts

---

## 8. Tips & Tricks

### Quickly Find Unread Messages
Type `is:unread` in the search bar.

### Find Large Emails Taking Up Quota
Search for `larger:10mb` to find big messages.

### Empty Trash and Junk
Right-click Trash or Junk > **Empty Folder**.

### Check Your Quota
Your storage usage is shown at the bottom-left of the webmail interface (bar showing used/total).

### Recover Deleted Messages
Check the **Trash** folder. Messages stay there until auto-purged (configured by admin, typically 30 days).

### Print a Message
Open the message > click **Actions** menu > **Print**.

### Download All Attachments
When a message has multiple attachments, click **Download All** to get a single ZIP file.

### Create a Quick Filter from a Message
Right-click a message > **New Filter** — pre-fills conditions based on that message.

---

## Features Not Available

The following standard Zimbra features are **disabled** in CXS Webmail:

| Feature | Status | Notes |
|---------|--------|-------|
| Calendar | Disabled | No appointment/scheduling |
| Tasks | Disabled | No task lists |
| Briefcase | Disabled | No file storage |
| Notebooks | Disabled | No wiki/notes |
| Chat | Removed | No instant messaging |
| Spell Check | Removed | Use browser's built-in spell check instead |
