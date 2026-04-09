# Privacy Policy

**Effective Date: March 19, 2026**

This Privacy Policy describes how Obius ("we," "us," or "our") collects, uses, stores, and protects your information when you use the Obius mobile and desktop applications, website, and related services (collectively, the "Service"). By accessing or using Obius, you acknowledge that you have read and understood this Privacy Policy. If you do not agree with the practices described herein, you should discontinue use of the Service immediately.

## Our Commitment to Privacy

Obius is built on a local-first architecture, which means your notes and content are created and stored directly on your device before anything is transmitted to a server. This design reflects our core belief that your data belongs to you. Cloud-based features such as sync, AI intelligence, and collaboration are entirely optional, and you retain full control over whether your data ever leaves your device.

## Information We Collect

When you use Obius, we may collect information in several categories depending on the features you choose to enable.

**Account Information.** If you create an account to access cloud-based features, we collect registration information such as your email address, display name, and avatar. This information is necessary to authenticate your identity, maintain your account, and provide you with access to sync, AI, and collaboration features. Your account is managed through our authentication infrastructure powered by Supabase, and your credentials are handled securely through their authentication services.

**Device Information.** When you register a device for cloud sync, we collect information about that device, including the device name, platform (iOS, Android, or web), application version, operating system version, and push notification token. This information allows us to facilitate sync across your devices, deliver push notifications when enabled, and diagnose technical issues that may be specific to certain platforms or software versions.

**Note Content.** If you enable cloud sync or AI features, the content of your notes and sections — including text, titles, and structural metadata such as section ordering, indentation levels, content types, color intents, and collapse states — is transmitted to our servers. This data is stored in our cloud infrastructure solely for the purpose of syncing your notes across devices and, when you invoke AI features, generating titles, summaries, and semantic search results. If you do not enable these features, your note content remains entirely on your device and is never transmitted to our servers.

**Sync Metadata.** When cloud sync is active, we maintain a changelog of sync operations to ensure data consistency across your devices. This changelog records the type of change made (creation, update, or deletion), the entity affected, timestamps from both your device and our server, and version information used for conflict resolution. This metadata is essential for providing reliable cross-device synchronization.

**AI-Generated Data.** When you use AI features, we generate and store AI-produced titles and summaries associated with your notes. We also generate vector embeddings of your note sections — mathematical representations of your content's meaning — which are stored on our servers to power semantic search functionality. These embeddings are created using OpenAI's embedding models and are associated with your user account.

**Payment Information.** If you purchase a premium subscription, payment processing is handled entirely by the Apple App Store or Google Play Store. We do not directly collect, store, or process your credit card numbers, bank account details, or other financial information. We may receive transaction confirmations and subscription status information from these platforms to manage your access to premium features.

## How We Use Your Information

We use the information we collect for the following purposes. We use your account information to authenticate you, maintain your account, and communicate with you regarding the Service. We use device information to facilitate cross-device sync, deliver push notifications, and troubleshoot platform-specific issues. We use your note content to provide cloud sync and, when you invoke AI features, to generate titles, summaries, and semantic search results through third-party AI providers. We use sync metadata to ensure data consistency and resolve conflicts when the same note is edited on multiple devices. We use AI-generated data such as embeddings to power semantic search within your notes. We do not use your information for advertising purposes. We do not sell your personal data or note content to third parties.

## Local-First Architecture and Privacy Mode

Obius is designed with a local-first philosophy. All core note-taking functionality operates using a local SQLite database on your device, meaning you can create, edit, organize, and search your notes without any data leaving your device or any internet connection whatsoever. Cloud features are additive and opt-in.

In addition, Obius offers a Privacy Mode setting within your user profile. When Privacy Mode is set to "private," your account operates in a strictly local-only configuration. In this mode, cloud sync and AI processing are disabled entirely, and no note content is transmitted to our servers or to any third-party provider. When Privacy Mode is set to "standard," cloud sync and AI features are available and operate as described in this Privacy Policy.

## Third-Party Service Providers

To deliver certain features of the Service, we engage the following categories of third-party providers.

**Cloud Infrastructure.** We use Supabase to provide authentication, database hosting, and serverless edge functions. Supabase processes your account information, device information, and — when sync is enabled — your note content. Supabase's infrastructure is used to store synced data and execute server-side logic such as sync operations and AI request routing. Supabase maintains its own privacy and security practices, and we encourage you to review their privacy policy.

**AI Providers.** When you invoke AI features, relevant portions of your note content are transmitted to third-party language model providers for processing. We currently use Anthropic (Claude) for generating note summaries and titles, and OpenAI for generating text embeddings that power semantic search. These providers process your content solely to return AI-generated results to you; however, their handling of data transmitted to them is subject to their respective privacy policies and data processing terms. We select AI providers that offer robust data handling commitments, but we encourage you to review their policies if you have concerns about how your content may be processed. You can avoid any data transmission to AI providers by disabling AI features or enabling Privacy Mode.

**App Store Platforms.** Subscription purchases and payment processing are handled by Apple (App Store) and Google (Google Play). These platforms collect payment and transaction information according to their own privacy policies. We receive only the information necessary to verify your subscription status.

## Data Storage and Security

We take the security of your data seriously. Your local data is stored in a SQLite database on your device, and its security is governed by the protections provided by your device's operating system, including device encryption and access controls. For cloud-synced data, we employ industry-standard security measures including encrypted connections for all data transmitted between your device and our servers, row-level security policies in our database ensuring that users can only access their own data, secure authentication through Supabase with hashed and salted credentials, and access-controlled serverless functions for all server-side operations.

While we implement reasonable technical and organizational measures to protect your data, no method of electronic transmission or storage is completely secure. We cannot guarantee absolute security, and you acknowledge that you transmit data to our Service at your own risk.

## Data Retention and Deletion

Your local data persists on your device for as long as the application is installed. We do not have access to or control over your local data.

For cloud-synced data, we retain your information for as long as your account is active and as needed to provide the Service to you. When you delete a note or section, we perform a soft deletion by marking the item with a deletion timestamp so that the deletion can be synced across your devices. Soft-deleted data may be permanently purged from our servers during routine maintenance cycles.

If you wish to delete your account and all associated cloud data, you may contact us at privacy@obius.io. Upon receiving a verified account deletion request, we will permanently delete your user profile, device registrations, synced notes, sections, AI-generated data, embeddings, and sync history from our servers. Please note that deletion of cloud data does not affect any data stored locally on your device, and we cannot delete data that has already been transmitted to third-party AI providers in accordance with their own retention policies.

If your account is terminated due to a violation of our Terms and Conditions, your local data will remain on your device, but your synced server data may be permanently deleted.

## Children's Privacy

Obius is not directed at children under the age of thirteen (13). We do not knowingly collect personal information from children under thirteen. If you are a parent or guardian and believe that your child has provided us with personal information without your consent, please contact us at privacy@obius.io. If we become aware that we have collected personal information from a child under thirteen, we will take steps to delete that information promptly.

## Your Rights and Choices

Depending on your jurisdiction, you may have certain rights regarding the personal information we hold about you. These may include the right to access the personal information we have collected about you, the right to request correction of inaccurate information, the right to request deletion of your data, the right to data portability, and the right to withdraw consent for optional data processing such as AI features and cloud sync. Because Obius is a local-first application, you inherently retain a complete copy of your data on your device at all times. You can exercise control over your data by enabling Privacy Mode to prevent any data from being transmitted to our servers, by disabling sync to keep your notes local-only, by choosing not to invoke AI features, or by contacting us to request account and data deletion.

To exercise any of these rights, please contact us at privacy@obius.io. We will respond to your request in a timely manner and in accordance with applicable law.

## Changes to This Privacy Policy

We may update this Privacy Policy from time to time to reflect changes in our practices, the Service, or applicable law. When we make material changes, we will notify you by updating the "Effective Date" at the top of this policy and, where appropriate, providing notice through the application or by email. Your continued use of the Service after the effective date of a revised Privacy Policy constitutes your acceptance of the updated terms. We encourage you to review this Privacy Policy periodically.

## Governing Law

This Privacy Policy is governed by and construed in accordance with the laws of the State of North Carolina, without regard to its conflict of law principles, consistent with the governing law provision in our Terms and Conditions.

## Contact Us

If you have any questions, concerns, or requests regarding this Privacy Policy or our data practices, please contact us at:

**Obius**
Email: privacy@obius.io
