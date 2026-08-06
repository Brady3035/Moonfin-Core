import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Approve and decline for one pending request, for the viewers Seerr lets
/// manage requests.
class SeerrApproveDeclineButtons extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  const SeerrApproveDeclineButtons({
    super.key,
    required this.isLoading,
    required this.onApprove,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: isLoading ? null : onApprove,
          icon: const Icon(
            Icons.check_circle_outline,
            color: Colors.green,
            size: 20,
          ),
          tooltip: l10n.approve,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        ),
        IconButton(
          onPressed: isLoading ? null : onDecline,
          icon: Icon(Icons.cancel_outlined, color: Colors.red[300], size: 20),
          tooltip: l10n.declineAction,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }
}
