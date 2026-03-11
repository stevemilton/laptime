import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/app_avatar.dart';
import '../data/comment_repository.dart';
import 'feed_screen.dart' show followingFeedProvider, nearbyFeedProvider;

/// Opens a bottom sheet displaying comments for a session.
void showCommentSheet(BuildContext context, WidgetRef ref, String sessionId) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _CommentSheet(sessionId: sessionId),
  );
}

class _CommentSheet extends ConsumerStatefulWidget {
  const _CommentSheet({required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends ConsumerState<_CommentSheet> {
  final _controller = TextEditingController();
  List<CommentItem> _comments = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  CommentRepository get _repo => CommentRepository(
        ref.read(databaseProvider),
        ref.read(supabaseClientProvider),
      );

  Future<void> _loadComments() async {
    try {
      final comments = await _repo.getSessionComments(widget.sessionId);
      if (mounted) {
        setState(() {
          _comments = comments;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Comments] Failed to load comments: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load comments. Please try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendComment() async {
    final body = _controller.text.trim();
    if (body.isEmpty) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _sending = true);
    _controller.clear();

    try {
      await _repo.addComment(
        sessionId: widget.sessionId,
        userId: user.id,
        body: body,
      );

      await _loadComments();

      // Invalidate feed providers so comment count updates on cards
      ref.invalidate(followingFeedProvider);
      ref.invalidate(nearbyFeedProvider);
    } catch (e) {
      debugPrint('[Comments] Failed to send comment: $e');
      if (mounted) {
        // Restore the text so the user doesn't lose their comment
        _controller.text = body;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not send comment. Please try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text('Comments', style: AppTypography.headlineSmall),
                    if (_comments.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${_comments.length}',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Comments list
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _comments.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.messageCircle,
                                  size: 40,
                                  color: AppColors.textTertiary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No comments yet',
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Be the first to comment',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: _comments.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 16),
                            itemBuilder: (context, index) {
                              final comment = _comments[index];
                              return _CommentRow(comment: comment);
                            },
                          ),
              ),

              // Input bar
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.border),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Add a comment...',
                          hintStyle: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textTertiary,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                        style: AppTypography.bodyMedium,
                        onSubmitted: (_) => _sendComment(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _sending ? null : _sendComment,
                      icon: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              LucideIcons.send,
                              color: AppColors.purple,
                              size: 20,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});

  final CommentItem comment;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppAvatar(
          imageUrl: comment.avatarUrl,
          initials: comment.displayName.isNotEmpty
              ? comment.displayName[0].toUpperCase()
              : null,
          size: 28,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    comment.displayName,
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    FormatUtils.formatRelativeDate(comment.createdAt),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                comment.body,
                style: AppTypography.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
