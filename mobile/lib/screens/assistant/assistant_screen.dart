import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/agent_message.dart';
import '../../providers/agent_provider.dart';
import '../../widgets/payment_plan_card.dart';

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

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
    ref.read(agentChatProvider.notifier).sendMessage(text);
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        IconData icon;
        Color color;
        switch (status) {
          case 'SUCCESS':
            icon = Icons.check_circle;
            color = Colors.green;
            break;
          case 'FAILED':
            icon = Icons.error;
            color = Colors.red;
            break;
          case 'CANCELLED':
            icon = Icons.cancel;
            color = Colors.orange;
            break;
          case 'PENDING':
          default:
            icon = Icons.hourglass_top;
            color = Colors.blue;
            break;
        }

        return AlertDialog(
          key: const Key('payment_result_dialog'),
          title: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  key: const Key('payment_result_title'),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message != null) ...[
                Text(message, key: const Key('payment_result_message')),
                const SizedBox(height: 12),
              ],
              Text('Amount: $currency $amount', key: const Key('payment_result_amount')),
              const SizedBox(height: 6),
              Text('Transaction ID: $transactionId', key: const Key('payment_result_tx_id')),
            ],
          ),
          actions: [
            TextButton(
              key: const Key('payment_result_primary_button'),
              onPressed: () {
                Navigator.of(ctx).pop();
                if (status == 'SUCCESS') {
                  context.go('/bills');
                }
              },
              child: Text(status == 'SUCCESS' ? 'View Bills' : 'OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(agentChatProvider);
    final theme = Theme.of(context);

    // Auto-scroll when new messages arrive
    ref.listen<AgentChatState>(agentChatProvider, (_, next) {
      _scrollToBottom();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing Assistant'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Conversation Area
            Expanded(
              child: chatState.messages.isEmpty
                  ? _buildEmptyState(theme)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: chatState.messages.length + (chatState.isLoading ? 1 : 0),
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

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 56,
              color: theme.primaryColor.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'How can I help you today?',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You can ask to view your bills, check due amounts, or prepare a bill payment.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    AgentMessage message,
    AgentChatState chatState,
    ThemeData theme,
  ) {
    final isUser = message.sender == MessageSender.user;

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
                  child: Icon(Icons.auto_awesome, size: 16, color: theme.primaryColor),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser
                        ? theme.primaryColor
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                  ),
                  child: Text(
                    message.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isUser ? Colors.white : Colors.black87,
                      height: 1.4,
                    ),
                  ),
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
                onCancel: () => ref
                    .read(agentChatProvider.notifier)
                    .cancelPlan(message.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingBubble(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.primaryColor.withOpacity(0.1),
            child: Icon(Icons.auto_awesome, size: 16, color: theme.primaryColor),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
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
                    color: Colors.grey.shade600,
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
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
                hintText: 'Type your message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey.shade300),
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
              color: canSend ? theme.primaryColor : Colors.grey.shade400,
            ),
            onPressed: canSend ? _sendMessage : null,
          ),
        ],
      ),
    );
  }
}
