import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../brands/example/example.dart';
import '../../../core/l10n/app_localizations.dart';
import '../domain/referral_share.dart';
import '../domain/rewards_models.dart';

/// The invitation link as a QR code, for a friend standing next to the
/// member. White ground whatever the theme: a scanner wants contrast, not
/// atmosphere.
Future<void> showReferralQrDialog(BuildContext context, String link) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('referral_qr_dialog'),
      title: Text(dialogContext.tr('Scan to sign up')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            // Tight on both axes: the dialog measures its content's
            // intrinsic width, and the code's own layout builder cannot
            // answer that question — a fixed box answers it for it.
            child: SizedBox.square(
              dimension: 220,
              child: QrImageView(
                data: link,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SelectableText(
            link,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: ExampleInk.secondary(dialogContext),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(dialogContext.tr('Close')),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// The three ways a member invites: share the invitation through the system
// sheet (with a clipboard fallback where sharing is unavailable), copy the
// link, or have the platform email a secure invitation. Shared by the phone
// summary and the desktop workspace, so both do exactly the same thing.
// ---------------------------------------------------------------------------

/// Puts [text] on the clipboard with the light haptic every copy here uses.
Future<void> copyToClipboard(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  HapticFeedback.lightImpact();
}

/// Copies the invitation link — or the bare code when no link resolves —
/// and confirms it on the nearest scaffold.
Future<void> copyReferralInvite(
  BuildContext context, {
  required String code,
  String? link,
}) async {
  await Clipboard.setData(ClipboardData(text: link ?? code));
  HapticFeedback.lightImpact();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(context.tr('Invite link copied'))),
  );
}

/// Shares the invitation through the platform sheet. Where sharing is
/// unavailable (some Android builds, some browsers) the same text lands on
/// the clipboard instead, so the flow always ends with something to paste.
Future<void> shareReferralInvite(
  BuildContext context, {
  required String appName,
  required ReferralSummary summary,
  required String code,
  String? link,
  Rect? origin,
}) async {
  final text = buildReferralShareText(
    appName: appName,
    referralCode: code,
    link: link,
    offer: summary.offer,
    translate: AppLocalizations.of(context).translate,
  );
  try {
    final result = await SharePlus.instance.share(
      ShareParams(
        title: context.tr('Share your {p0} invite', {'p0': appName}),
        subject: context.tr("You're invited to {p0}", {'p0': appName}),
        text: text,
        sharePositionOrigin: origin,
      ),
    );
    if (result.status != ShareResultStatus.unavailable) return;
  } catch (_) {
    // Fall through to the clipboard.
  }
  if (!context.mounted) return;
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(context.tr('Invitation copied. Paste it to invite a friend.')),
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr(
            'Could not share. Use Copy invite link to copy your invitation.')),
      ),
    );
  }
}

/// The share origin for iPad's popover: the bounds of [context]'s render box.
Rect? shareOriginOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Who to email an invitation to.
class ReferralInvitationRequest {
  const ReferralInvitationRequest({required this.email, this.name});

  final String email;
  final String? name;
}

/// Validates an email the way the invitation dialog always has: something
/// before the @, something after it, and a dot in the domain.
String? referralInvitationEmailError(BuildContext context, String? value) {
  final email = value?.trim() ?? '';
  final at = email.indexOf('@');
  if (at <= 0 ||
      at == email.length - 1 ||
      !email.substring(at).contains('.')) {
    return context.tr('Enter a valid email address');
  }
  return null;
}

/// The name and email fields of an invitation, for a dialog or an inline
/// form. Inputs are 16 px so a phone browser never zooms into them.
class ReferralInvitationFields extends StatelessWidget {
  const ReferralInvitationFields({
    required this.nameController,
    required this.emailController,
    this.enabled = true,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController nameController;
  final TextEditingController emailController;
  final bool enabled;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    const inputStyle = TextStyle(fontSize: 16);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const Key('referral_invitation_name'),
          controller: nameController,
          enabled: enabled,
          style: inputStyle,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: context.tr('Name (optional)')),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          key: const Key('referral_invitation_email'),
          controller: emailController,
          enabled: enabled,
          style: inputStyle,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.send,
          decoration: InputDecoration(labelText: context.tr('Email')),
          validator: (value) => referralInvitationEmailError(context, value),
          onFieldSubmitted: (_) => onSubmitted?.call(),
        ),
      ],
    );
  }
}

/// Asks who to invite. Resolves with the request, or null when dismissed.
Future<ReferralInvitationRequest?> showReferralInvitationDialog(
    BuildContext context) async {
  final emailController = TextEditingController();
  final nameController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  void submit(BuildContext dialogContext) {
    if (formKey.currentState?.validate() != true) return;
    final name = nameController.text.trim();
    Navigator.pop(
      dialogContext,
      ReferralInvitationRequest(
        email: emailController.text.trim(),
        name: name.isEmpty ? null : name,
      ),
    );
  }

  final submission = await showDialog<ReferralInvitationRequest>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.tr('Send referral invitation')),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context
                  .tr('We will email a secure invitation link to this person.'),
            ),
            const SizedBox(height: AppSpacing.md),
            ReferralInvitationFields(
              nameController: nameController,
              emailController: emailController,
              onSubmitted: () => submit(dialogContext),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton.icon(
          onPressed: () => submit(dialogContext),
          icon: const Icon(Icons.send_rounded),
          label: Text(context.tr('Send invitation')),
        ),
      ],
    ),
  );
  // The dialog's exit transition still reads the controllers.
  await Future<void>.delayed(const Duration(milliseconds: 350));
  emailController.dispose();
  nameController.dispose();
  return submission;
}

/// The invitation as an inline form, for the desktop Share tab: the same
/// fields and validation as the dialog, one Send control, busy while the
/// platform is emailing.
class ReferralInvitationForm extends StatefulWidget {
  const ReferralInvitationForm({
    required this.onSend,
    this.busy = false,
    super.key,
  });

  final ValueChanged<ReferralInvitationRequest> onSend;
  final bool busy;

  @override
  State<ReferralInvitationForm> createState() => _ReferralInvitationFormState();
}

class _ReferralInvitationFormState extends State<ReferralInvitationForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.busy) return;
    if (_formKey.currentState?.validate() != true) return;
    final name = _name.text.trim();
    widget.onSend(ReferralInvitationRequest(
      email: _email.text.trim(),
      name: name.isEmpty ? null : name,
    ));
    _email.clear();
    _name.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('We will email a secure invitation link to this person.'),
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: ExampleInk.secondary(context),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ReferralInvitationFields(
            nameController: _name,
            emailController: _email,
            enabled: !widget.busy,
            onSubmitted: _submit,
          ),
          const SizedBox(height: AppSpacing.md),
          ExampleGlassButton(
            key: const Key('referral_invitation_send'),
            label: context.tr('Send invitation'),
            icon: Icons.send_rounded,
            sheen: false,
            loading: widget.busy,
            loadingSemanticsLabel: 'Sending invitation',
            onPressed: widget.busy ? null : _submit,
          ),
        ],
      ),
    );
  }
}
