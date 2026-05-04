# S3 Hosting Setup

> Step-by-step guide to connecting an S3 bucket to Podedge.
> **Audience:** podcasters setting up hosting for the first time.

<!--
Changelog
- 2026-05-01: Restructured. Added automated script path. Moved signed-URL note to bottom. Console and script paths side by side.
- 2026-05-01: Repositioned CloudFront + OAC as recommended setup.
- 2026-05-01: Initial draft.
-->

Podedge uploads your audio files and RSS feed to an S3 bucket that you own. Listeners download files through a CloudFront CDN, which serves them over HTTPS from a global edge network. Your S3 bucket stays completely private — only your CloudFront distribution can read from it.

**You will need an AWS account.** If you don't have one, create one at [aws.amazon.com](https://aws.amazon.com). If you prefer Cloudflare R2, DigitalOcean Spaces, or MinIO, skip to [S3-compatible alternatives](#s3-compatible-alternatives).

## Choose your setup path

You can set up hosting in two ways — pick whichever you're more comfortable with:

| Path | Best for | Time |
|---|---|---|
| [**Automated script**](#automated-setup-script) | Anyone comfortable with a terminal | ~2 minutes |
| [**AWS Console (manual)**](#manual-setup-aws-console) | Anyone who prefers a visual interface | ~15 minutes |

Both paths create the same result: a private S3 bucket, a CloudFront distribution with Origin Access Control, and a least-privilege IAM user.

---

## Automated Setup Script

The script creates everything in one run: S3 bucket, CloudFront distribution with OAC, bucket policy, and IAM user with least-privilege credentials. At the end it prints the exact values to enter in Podedge.

### Prerequisites: Install the AWS CLI

The script requires the AWS CLI v2. If you don't have it:

**macOS (Homebrew):**
```bash
brew install awscli
```

**macOS (official installer):**
Download from [docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

**Verify it's installed:**
```bash
aws --version
# Should print: aws-cli/2.x.x ...
```

**Configure your credentials** (one-time setup — use your personal or admin AWS credentials here, NOT the Podedge IAM user which doesn't exist yet):
```bash
aws configure
# Enter your Access Key ID, Secret Access Key, default region, and output format (json)
```

See [AWS CLI Configuration Guide](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html) for details.

### Run the script

From the Podedge repo root:

```bash
./scripts/setup-s3-hosting.sh
```

The script will ask for:
1. **Bucket name** — a globally unique, lowercase name (e.g. `my-podcast-media`)
2. **AWS region** — the region closest to your listeners (e.g. `us-east-1`)

It then creates everything and prints a summary:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Setup complete! Enter these values in Podedge (Settings → Hosts → Add Host):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Bucket:            my-podcast-media
  Region:            us-east-1
  Public Base URL:   https://d1234abcd5678.cloudfront.net
  Access Key ID:     AKIAIOSFODNN7EXAMPLE
  Secret Access Key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

⚠  Save the Secret Access Key now — it cannot be retrieved again.
```

Copy these values into Podedge and you're done. Skip to [Enter credentials in Podedge](#enter-credentials-in-podedge).

> **What the script creates:** a private S3 bucket (Block Public Access ON), a CloudFront distribution with Origin Access Control, a bucket policy that allows only that distribution to read, and an IAM user (`podedge-<bucket-name>`) with only the 5 S3 permissions Podedge needs. Nothing more.

---

## Manual Setup (AWS Console)

Follow these steps in the [AWS Console](https://console.aws.amazon.com) if you prefer a visual interface.

### Step 1 — Create the S3 bucket

1. Navigate to **S3 → Create bucket**.
2. **Bucket name** — choose a globally unique, lowercase name (e.g. `my-podcast-media`). You cannot change this later.
3. **AWS Region** — pick the region closest to your listeners (e.g. `us-east-1`). Note the region code.
4. **Block Public Access** — leave all four checkboxes **checked** (the default). The bucket stays private.
5. Click **Create bucket**.

### Step 2 — Create a CloudFront distribution

1. Navigate to **CloudFront → Create distribution**.
2. **Origin domain** — select your S3 bucket from the dropdown.
3. **Origin access** — select **Origin access control settings (recommended)**.
4. Click **Create new OAC**. Accept the defaults and click **Create**.
5. **Viewer protocol policy** — set to **Redirect HTTP to HTTPS**.
6. Click **Create distribution**.

CloudFront will show a blue banner:

> **The S3 bucket policy needs to be updated**

Click **Copy policy**. You'll paste it in the next step.

### Step 3 — Set the bucket policy

1. Go back to **S3 → your bucket → Permissions → Bucket policy → Edit**.
2. Paste the policy you copied from CloudFront. It looks like this:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowCloudFrontServicePrincipal",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudfront.amazonaws.com"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "arn:aws:cloudfront::YOUR-ACCOUNT-ID:distribution/YOUR-DISTRIBUTION-ID"
                }
            }
        }
    ]
}
```

3. Click **Save changes**.

This allows **only your CloudFront distribution** to read from the bucket. The `AWS:SourceArn` condition locks it to your specific distribution — no one else can access the files, even if they know the S3 URL.

### Step 4 — Note your public base URL

Find the **Distribution domain name** on the CloudFront detail page:

```
https://d1234abcd5678.cloudfront.net
```

This is the **Public Base URL** you'll enter in Podedge. CloudFront takes 5–10 minutes to deploy.

**Optional: custom domain.** To use your own domain (e.g. `https://media.mypodcast.com`):
1. Edit the distribution → add your domain under **Alternate domain names (CNAMEs)**.
2. Request an SSL certificate in **AWS Certificate Manager** (must be in `us-east-1`).
3. Add a CNAME record in your DNS pointing to the CloudFront domain.

### Step 5 — Create a least-privilege IAM user

1. Navigate to **IAM → Users → Create user**.
2. **User name** — e.g. `podedge-publisher`.
3. **Console access** — leave **unchecked**. This user only needs programmatic access.
4. Click through to **Create user**.

### Step 6 — Attach the IAM policy

1. Click the user → **Permissions → Add permissions → Create inline policy**.
2. Switch to the **JSON** editor and paste:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PodedgePublish",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::YOUR-BUCKET-NAME",
                "arn:aws:s3:::YOUR-BUCKET-NAME/*"
            ]
        }
    ]
}
```

3. Name it `PodedgePublishPolicy` and click **Create policy**.

**Why each permission:**

| Permission | Purpose |
|---|---|
| `s3:PutObject` | Upload audio, transcripts, and the RSS feed |
| `s3:GetObject` | Verify uploaded content and check if a file exists (HEAD Object) |
| `s3:DeleteObject` | Remove files when unpublishing |
| `s3:ListBucket` | Lets HEAD Object return 404 (not found) instead of 403 (denied) |

**What's excluded and why:**

| Not included | Reason |
|---|---|
| `s3:*` wildcard | Least privilege — only 5 actions needed |
| `s3:DeleteBucket` | Can't accidentally delete the bucket |
| `s3:PutBucketPolicy` | Can't change bucket permissions |
| Any other AWS service | Podedge only uses S3 |

The policy is scoped to one bucket. This user cannot touch anything else in your AWS account.

### Step 7 — Create the access key

1. On the user page → **Security credentials → Access keys → Create access key**.
2. Select **Application running outside AWS** → **Next** → **Create access key**.
3. **Copy both values now** — the Secret Access Key is shown only once:
   - **Access Key ID** — starts with `AKIA`
   - **Secret Access Key** — a 40-character string

---

## Enter Credentials in Podedge

Open Podedge → **Settings → Hosts → Add Host** (or complete this during onboarding).

| Podedge field | What to enter | Example |
|---|---|---|
| Display Name | Any friendly label | `My Podcast S3` |
| Bucket | Your S3 bucket name | `my-podcast-media` |
| Region | AWS region code | `us-east-1` |
| Path Prefix | Optional subfolder | `shows/my-show` (or leave empty) |
| Public Base URL | Your CloudFront domain | `https://d1234abcd5678.cloudfront.net` |
| Access Key ID | From the IAM user | `AKIAIOSFODNN7EXAMPLE` |
| Secret Access Key | From the IAM user | *(stored in macOS Keychain)* |
| Custom Endpoint | Leave empty for AWS S3 | Only for R2/Spaces/MinIO |

---

## S3-Compatible Alternatives

Podedge works with any S3-compatible storage via the **Custom Endpoint** field.

### Cloudflare R2

No egress fees — cost-effective for podcast audio.

1. Cloudflare dashboard → **R2 → Create bucket**.
2. Create an API token with **Object Read & Write** scoped to your bucket.
3. In Podedge:
   - **Custom Endpoint:** `https://YOUR-ACCOUNT-ID.r2.cloudflarestorage.com`
   - **Region:** `auto`

### DigitalOcean Spaces

1. Create a Space in the DO control panel.
2. Generate a Spaces key under **API → Spaces Keys**.
3. In Podedge:
   - **Custom Endpoint:** `https://REGION.digitaloceanspaces.com`
   - **Region:** your Space's region (e.g. `nyc3`)

### MinIO (self-hosted)

In Podedge:
- **Custom Endpoint:** your MinIO URL (e.g. `https://minio.example.com`)
- **Region:** `us-east-1` (MinIO accepts any value)

---

## Security Notes

- **Your S3 bucket is private.** Block Public Access stays fully enabled. Files are only reachable through your CloudFront distribution.
- **CloudFront OAC** locks bucket access to your specific distribution ARN — not to CloudFront in general.
- **Podedge uploads directly to S3** using the IAM credentials. Uploads don't go through CloudFront.
- **Credentials are stored in the macOS Keychain**, never written to disk or logs.
- **Use a dedicated IAM user** — never your root AWS account or an admin user.
- **Rotate keys periodically.** Update in Podedge under Settings → Hosts → Edit, then delete the old key in IAM.
- **Logs are redacted.** If you export diagnostic logs, they will not contain your keys.

---

## Why Not Signed URLs?

You might wonder why Podedge doesn't use S3 signed URLs for extra security. The reason is how podcasting works: the RSS feed contains a permanent `<enclosure>` URL for each episode. Podcast apps (Apple Podcasts, Spotify, Overcast, etc.) download episodes on their own schedule — sometimes hours or days after fetching the feed. Signed URLs expire, which would break downloads for any listener who doesn't fetch the file within the expiry window.

CloudFront + OAC gives you the security benefit (private bucket, controlled access) without the expiry problem. The CloudFront URLs are permanent and stable, which is what RSS requires.
