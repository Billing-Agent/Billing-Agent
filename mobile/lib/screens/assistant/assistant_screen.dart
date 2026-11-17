import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/agent_message.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/agent_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/payment_plan_card.dart';
import '../../widgets/payment_result_dialog.dart';

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Route<dynamic>? _paymentDialogRoute;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    _textController.clear();
    _sendText(text);
  }

  void _sendText(String text) {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return;

    ref.read(agentChatProvider.notifier).sendMessage(trimmedText);
    _scrollToBottom();
  }

  void _confirmPayment(AgentMessage message) {
    if (message.confirmationId == null) return;

    ref.read(agentChatProvider.notifier).confirmPaymentPlan(
          messageId: message.id,
          confirmationId: message.confirmationId!,
          onError: (errorMsg) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(errorMsg)),
            );
          },
          onPaymentResult: ({
            required String status,
            required String title,
            required String transactionId,
            required String amount,
            required String currency,
            String? message,
          }) {
            if (!mounted) return;
            _showPaymentResultDialog(
              status: status,
              title: title,
              transactionId: transactionId,
              amount: amount,
              currency: currency,
              message: message,
            );
          },
        );
  }

  void _showPaymentResultDialog({
    required String status,
    required String title,
    required String transactionId,
    required String amount,
    required String currency,
    String? message,
  }) {
    Route<dynamic>? openedRoute;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        openedRoute = ModalRoute.of(ctx);
        _paymentDialogRoute = openedRoute;
        return PaymentResultDialog(
          status: status,
          title: title,
          transactionId: transactionId,
          amount: amount,
          currency: currency,
          message: message,
          onPrimary: () {
            Navigator.of(ctx).pop();
            if (status == 'SUCCESS') {
              context.go('/bills');
            }
          },
        );
      },
    ).whenComplete(() {
      if (identical(_paymentDialogRoute, openedRoute)) {
        _paymentDialogRoute = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(agentChatProvider);
    final theme = Theme.of(context);

    ref.listen<AuthenticatedSession?>(
      authenticatedSessionProvider,
      (previous, next) {
        if (identical(previous, next) || !mounted) return;
        _textController.clear();
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
        final dialogRoute = _paymentDialogRoute;
        if (dialogRoute != null) {
          Navigator.of(context, rootNavigator: true).removeRoute(dialogRoute);
          _paymentDialogRoute = null;
        }
      },
    );

    // Auto-scroll when new messages arrive
    ref.listen<AgentChatState>(agentChatProvider, (_, next) {
      _scrollToBottom();
    });

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 20,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: AppConstants.spacingMedium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Billing Assistant'),
                  Text(
                    'Plans with you. Payments require confirmation.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Conversation Area
            Expanded(
              child: chatState.messages.isEmpty
                  ? _buildEmptyState(chatState, theme)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      itemCount: chatState.messages.length +
                          (chatState.isLoading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == chatState.messages.length) {
                          return _buildLoadingBubble(theme);
                        }
                        final message = chatState.messages[index];
                        return _buildMessageBubble(message, chatState, theme);
                      },
                    ),
            ),

            // Input Area
            _buildInputArea(chatState, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AgentChatState chatState, ThemeData theme) {
    final semantic = AppSemanticColors.of(context);
    final canSend = !chatState.isLoading && !chatState.isConfirming;
    const prompts = [
      'Show my bills',
      'Find my electricity bill',
      'Help me prepare a bill payment',
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.spacingXLarge),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: AppConstants.spacingXXLarge),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 34,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: AppConstants.spacingLarge),
          Text(
            'Your billing copilot',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSmall),
          Text(
            'Ask about your bills, due amounts, or get help preparing a payment.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppConstants.spacingLarge),
          Container(
            padding: const EdgeInsets.all(AppConstants.spacingMedium),
            decoration: BoxDecoration(
              color: semantic.informationContainer,
              borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
              border: Border.all(color: semantic.information.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 20,
                  color: semantic.onInformationContainer,
                ),
                const SizedBox(width: AppConstants.spacingSmall),
                Expanded(
                  child: Text(
                    'I can prepare a payment; you must confirm it.',
                    key: const Key('assistant_payment_boundary'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: semantic.onInformationContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacingXLarge),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Try asking',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingSmall),
          Wrap(
            spacing: AppConstants.spacingSmall,
            runSpacing: AppConstants.spacingSmall,
            alignment: WrapAlignment.center,
            children: [
              for (final prompt in prompts)
                ActionChip(
                  label: Text(prompt),
                  onPressed: canSend ? () => _sendText(prompt) : null,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    AgentMessage message,
    AgentChatState chatState,
    ThemeData theme,
  ) {
    final isUser = message.sender == MessageSender.user;
    final semantic = AppSemanticColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.primaryColor.withOpacity(0.1),
                  child: Icon(Icons.auto_awesome,
                      size: 16, color: theme.primaryColor),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      isUser ? 'You' : 'Billing Assistant',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppConstants.spacingXSmall),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spacingLarge,
                        vertical: AppConstants.spacingMedium,
                      ),
                      decoration: BoxDecoration(
                        color: isUser
                            ? theme.colorScheme.primary
                            : semantic.surfaceSubtle,
                        border:
                            isUser ? null : Border.all(color: semantic.border),
                        borderRadius: BorderRadius.only(
                          topLeft:
                              const Radius.circular(AppConstants.radiusLarge),
                          topRight:
                              const Radius.circular(AppConstants.radiusLarge),
                          bottomLeft: Radius.circular(
                            isUser
                                ? AppConstants.radiusLarge
                                : AppConstants.spacingXSmall,
                          ),
                          bottomRight: Radius.circular(
                            isUser
                                ? AppConstants.spacingXSmall
                                : AppConstants.radiusLarge,
                          ),
                        ),
                      ),
                      child: Text(
                        message.text,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isUser
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Structured Payment Plan Card (if present)
          if (!isUser && message.hasPaymentPlan)
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 4),
              child: PaymentPlanCard(
                plan: message.paymentPlan!,
                cardState: message.cardState,
                isConfirming: chatState.isConfirming,
                errorMessage: message.errorMessage,
                onConfirm: () => _confirmPayment(message),
                onCancel: () =>
                    ref.read(agentChatProvider.notifier).cancelPlan(message.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingBubble(ThemeData theme) {
    final semantic = AppSemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.primaryColor.withOpacity(0.1),
            child:
                Icon(Icons.auto_awesome, size: 16, color: theme.primaryColor),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: semantic.surfaceSubtle,
              borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
              border: Border.all(color: semantic.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.primaryColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Thinking...',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(AgentChatState chatState, ThemeData theme) {
    final canSend = !chatState.isLoading && !chatState.isConfirming;
    final semantic = AppSemanticColors.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingLarge,
        AppConstants.spacingMedium,
        AppConstants.spacingLarge,
        AppConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: semantic.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('assistant_text_field'),
              controller: _textController,
              enabled: canSend,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: 'Ask about your bills…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
                  borderSide: BorderSide(color: semantic.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
                  borderSide: BorderSide(color: semantic.border),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('assistant_send_button'),
            icon: Icon(
              Icons.send_rounded,
              color: canSend
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            onPressed: canSend ? _sendMessage : null,
          ),
        ],
      ),
    );
  }
}
