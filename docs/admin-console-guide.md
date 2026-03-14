# CXS Admin Console Guide

Access: **https://admin.cloudxspace.com** (or https://mail.cloudxspace.com:7071)

Login with: `admin@cloudxspace.com` and your admin password.

---

## Navigation Overview

The admin console has 5 main sections in the left navigation tree:

1. **Home** - Dashboard
2. **Monitor** - Server status & statistics
3. **Manage** - Accounts, distribution lists, resources
4. **Configure** - Domains, COS, servers, global settings, zimlets
5. **Tools and Migration** - Mail queues, search

---

## 1. Home (Dashboard)

The landing page after login. Shows quick links to common tasks:
- Create a new account
- View server status
- Check mail queues

---

## 2. Monitor

### 2.1 Server Status

**Path:** Monitor > Server Status

Shows the running/stopped status of all Zimbra services:
- LDAP
- Mailbox (mailboxd)
- MTA (Postfix)
- Proxy (nginx)
- Antivirus (ClamAV)
- Antispam (SpamAssassin)
- Logger
- SNMP
- DNS Cache

### 2.2 Server Statistics

**Path:** Monitor > Server Statistics

View performance metrics:
- Message count (received/sent over time)
- Message volume (bytes)
- Anti-spam/anti-virus activity
- Disk usage
- Server-level detailed statistics

---

## 3. Manage

### 3.1 Accounts

**Path:** Manage > Accounts

This is where you create and manage user mailboxes.

#### Create a New Account
1. Click **New** in the toolbar
2. Fill in:
   - **Account name**: the email address (e.g., `user@cloudxspace.com`)
   - **First/Last name**: display name
   - **Password**: initial password
   - **Class of Service**: select a COS (usually `default`)
3. Click **Finish**

#### Edit an Account
1. Find the account in the list (use search if needed)
2. Double-click to open
3. Tabs available:
   - **General**: Name, status (active/locked/closed/maintenance), password
   - **Aliases**: Add alternate email addresses
   - **Forwarding**: Set mail forwarding address
   - **Features**: Enable/disable features for this user
   - **Preferences**: Override default preferences
   - **Zimlets**: Enable/disable zimlets
   - **Advanced**: Quota, attachment limits, password policy
   - **Member Of**: Shows distribution lists this account belongs to

#### Common Account Actions
- **Change password**: Edit account > General tab > enter new password
- **Lock account**: Edit account > General tab > Status = Locked
- **Set quota**: Edit account > Advanced tab > Quota field (e.g., `500MB`)
- **Delete account**: Select account > click Delete in toolbar

#### Account Statuses
| Status | Meaning |
|--------|---------|
| Active | Normal, can send/receive |
| Locked | Cannot login, mail still delivered |
| Closed | Cannot login, mail bounced |
| Maintenance | Temporarily offline |
| Pending | Awaiting activation |

### 3.2 Aliases

**Path:** Manage > Aliases

Aliases are alternate email addresses that deliver to an existing account.

- **Create alias**: New > enter alias address > select target account
- **Delete alias**: Select > Delete

### 3.3 Distribution Lists

**Path:** Manage > Distribution Lists

Distribution lists (DLs) are group email addresses. Mail sent to a DL is delivered to all members.

#### Create a Distribution List
1. Click **New**
2. Enter list name (e.g., `team@cloudxspace.com`)
3. Go to **Members** tab
4. Add members by email address
5. Click **Save**

#### DL Settings
- **Members**: Add/remove email addresses
- **Owners**: Who can manage this list
- **Preferences**: Subscription policy (open, closed, approval required)
- **Reply-to**: Set a reply-to address for the list

### 3.4 Resources

**Path:** Manage > Resources

Resources represent shared equipment or meeting rooms (e.g., conference rooms). Less relevant for a mail-only deployment, but available if needed.

---

## 4. Configure

### 4.1 Class of Service (COS)

**Path:** Configure > Class of Service

A COS defines default settings for a group of accounts. The `default` COS is applied to all new accounts unless overridden.

#### Key COS Settings

**Features tab** - Enable/disable features for all accounts in this COS:
- Mail features (forwarding, filters, out-of-office)
- Contacts/Address book
- Skin change ability

**Advanced tab**:
- **Mail quota**: Maximum mailbox size (e.g., `1GB`)
- **Max message size**: Largest email allowed (send/receive)
- **Attachment size limit**
- **Password policy**: Min/max length, complexity, expiry, lockout
- **Session timeout**: How long before auto-logout

**Preferences tab** - Default preferences for users:
- Default mail view (conversation vs. message list)
- Compose format (HTML vs. plain text)
- Reading pane position
- Items per page
- Mail polling interval

### 4.2 Domains

**Path:** Configure > Domains

Manage email domains hosted on this server.

#### Domain Settings
- **General**: Domain name, status, description
- **GAL (Global Address List)**: How the address directory works
  - Mode: Internal (LDAP), External, or Both
  - Autocomplete settings
- **Authentication**: How users authenticate
  - Internal (Zimbra LDAP)
  - External LDAP / Active Directory
- **Advanced**: Default COS, public hostname, quota per domain

### 4.3 Servers

**Path:** Configure > Servers

View and configure the mail server.

#### Server Settings
- **General**: Hostname, service enable/disable
- **MTA**: SMTP relay host, trusted networks, SASL auth
- **IMAP/POP**: Port configuration, SSL settings
- **Proxy**: nginx proxy configuration
- **Volumes**: Manage mail storage volumes (primary, secondary, index)

#### Manage Volumes
Volumes define where mail data is physically stored:
- **Primary message volume**: Where new mail is stored
- **Secondary volume**: For older/archived mail (HSM)
- **Index volume**: Full-text search index

### 4.4 Global Settings

**Path:** Configure > Global Settings

System-wide settings that apply to all domains and accounts (unless overridden at domain or COS level).

**Key tabs:**

| Tab | What it controls |
|-----|-----------------|
| General | Default domain, thread counts, purge interval |
| Attachments | Blocked file extensions, size limits |
| MTA | SMTP relay, max message size, SASL, TLS, trusted networks |
| IMAP/POP | Enable/disable, ports, SSL, thread counts |
| Anti-Spam | Kill threshold, tag threshold, spam/ham training accounts |
| Anti-Virus | Update frequency, block encrypted archives, admin notifications |
| Retention Policy | Auto-delete policies for mail, trash, spam |
| Skin | Default skin, available skins |

### 4.5 Zimlets

**Path:** Configure > Zimlets

Zimlets are extensions that add functionality to the webmail interface. You can:
- **Enable**: Zimlet is available and on by default
- **Disable**: Zimlet is not available
- **Mandatory**: Zimlet is always on, user cannot disable it

### 4.6 Admin Extensions

**Path:** Configure > Admin Extensions

Extensions that add functionality to the admin console itself.

---

## 5. Tools and Migration

### 5.1 Mail Queues

**Path:** Tools and Migration > Mail Queues

View and manage the Postfix mail queue. Shows messages in these queues:

| Queue | Meaning |
|-------|---------|
| Deferred | Delivery failed, will retry |
| Active | Currently being delivered |
| Incoming | Just received, waiting to process |
| Hold | Manually held, will not deliver |
| Corrupt | Damaged queue files |

**Actions on queued messages:**
- **Hold**: Prevent delivery
- **Release**: Resume delivery of held messages
- **Requeue**: Retry delivery
- **Delete**: Remove from queue

### 5.2 Account Search

**Path:** Tools and Migration > Search

Search for accounts with advanced filters:
- By name, email, or display name
- By status (active, locked, etc.)
- By last login date
- By domain or server
- By Class of Service

---

## Common Admin Tasks

### Set/Reset a User's Password

```bash
# SSH into the server or docker exec
su - zimbra -c "zmprov sp user@cloudxspace.com NewPassword123"
```

Or in the admin console: Manage > Accounts > double-click account > set password.

### Check Service Status

```bash
su - zimbra -c "zmcontrol status"
```

Or in admin console: Monitor > Server Status.

### Restart All Services

```bash
su - zimbra -c "zmcontrol restart"
```

### Restart a Single Service

```bash
su - zimbra -c "zmmailboxdctl restart"   # Mailbox (Jetty)
su - zimbra -c "zmproxyctl restart"       # Proxy (nginx)
su - zimbra -c "zmmtactl restart"         # MTA (Postfix)
su - zimbra -c "ldap restart"             # LDAP
```

### View Logs

```bash
# Mailbox log (web client, admin console, SOAP)
tail -f /opt/zimbra/log/mailbox.log

# Mail delivery log
tail -f /var/log/mail.log

# Audit log (logins, password changes)
tail -f /opt/zimbra/log/audit.log

# nginx proxy log
tail -f /opt/zimbra/log/nginx.access.log
```

### Manage Mailbox Quota

```bash
# Check quota usage
su - zimbra -c "zmprov gmi user@cloudxspace.com"

# Set quota (0 = unlimited)
su - zimbra -c "zmprov ma user@cloudxspace.com zimbraMailQuota 1073741824"  # 1GB
```

Or in admin console: Manage > Accounts > edit > Advanced tab > Quota.

### Create Account via CLI

```bash
su - zimbra -c "zmprov ca user@cloudxspace.com Password123 displayName 'John Doe'"
```

### Create Distribution List via CLI

```bash
su - zimbra -c "zmprov cdl team@cloudxspace.com"
su - zimbra -c "zmprov adlm team@cloudxspace.com user1@cloudxspace.com user2@cloudxspace.com"
```

### Flush Mail Queue

```bash
su - zimbra -c "postqueue -f"        # Retry all deferred
su - zimbra -c "postsuper -d ALL"    # Delete all queued mail (caution!)
```

### View/Manage SSL Certificate

```bash
su - zimbra -c "zmcertmgr viewdeployedcrt"  # View current cert
```

### Backup a Mailbox

```bash
su - zimbra -c "zmmailbox -z -m user@cloudxspace.com getRestURL '//?fmt=tgz' > /tmp/backup.tgz"
```

### Restore a Mailbox

```bash
su - zimbra -c "zmmailbox -z -m user@cloudxspace.com postRestURL '//?fmt=tgz&resolve=reset' /tmp/backup.tgz"
```

---

## Features Disabled in CXS Build

The following stock Zimbra features are **not available** in this build:

| Feature | Status |
|---------|--------|
| Calendar/Scheduling | Disabled |
| Tasks | Disabled |
| Briefcase/Documents | Disabled |
| Notebooks | Disabled |
| Chat | Removed |
| Spell Check (Aspell) | Removed |
| Apache (zimbraApache) | Removed |

The admin console still shows some of these settings (e.g., calendar preferences in COS), but they have no effect since the features are disabled at the server level.
