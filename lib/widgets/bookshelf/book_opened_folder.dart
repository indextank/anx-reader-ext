import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/widgets/bookshelf/book_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BookOpenedFolder extends ConsumerStatefulWidget {
  const BookOpenedFolder({
    super.key,
    required this.books,
    required this.groupName,
  });

  final List<Book> books;
  final String groupName;

  @override
  ConsumerState<BookOpenedFolder> createState() => _BookOpenedFolderState();
}

class _BookOpenedFolderState extends ConsumerState<BookOpenedFolder> {
  bool isEditing = false;
  bool isEditingName = false;
  bool _updatingName = false;
  bool _nameUpdateFailed = false;
  late final List<Book> books = [...widget.books];
  late final TextEditingController _nameController;
  late String currentGroupName = widget.groupName;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: currentGroupName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _updateGroupName() async {
    if (books.isEmpty || _updatingName) return;
    final groupId = books.first.groupId;
    if (groupId <= 0) return;

    setState(() {
      _updatingName = true;
      _nameUpdateFailed = false;
    });
    try {
      final group = await ref.read(groupDaoProvider.notifier).getGroup(groupId);
      if (group == null) return;
      await ref
          .read(groupDaoProvider.notifier)
          .updateGroup(group.copyWith(name: _nameController.text));
      if (!mounted) return;
      setState(() {
        currentGroupName = _nameController.text;
        isEditingName = false;
      });
    } catch (_) {
      if (mounted) setState(() => _nameUpdateFailed = true);
    } finally {
      _updatingName = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppDialog(
      title: currentGroupName,
      content: SizedBox(
        width: MediaQuery.of(context).size.width *
            AppBookshelfTokens.folderDialogWidthFactor,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isEditingName) ...[
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _nameController,
                        autofocus: true,
                        enabled: !_updatingName,
                        onSubmitted: (_) => _updateGroupName(),
                      ),
                    ),
                    AppIconButton(
                      icon: Icons.check,
                      semanticLabel: l10n.commonSave,
                      tooltip: l10n.commonSave,
                      isLoading: _updatingName,
                      onPressed: _updateGroupName,
                    ),
                    AppIconButton(
                      icon: Icons.close,
                      semanticLabel: l10n.commonCancel,
                      tooltip: l10n.commonCancel,
                      enabled: !_updatingName,
                      onPressed: () {
                        setState(() {
                          _nameController.text = currentGroupName;
                          isEditingName = false;
                          _nameUpdateFailed = false;
                        });
                      },
                    ),
                  ],
                ),
                if (_nameUpdateFailed)
                  AppInlineFeedback(onRetry: _updateGroupName),
                SizedBox(height: AppSpacing.tokens.s12),
              ] else
                Align(
                  alignment: Alignment.centerRight,
                  child: AppButton(
                    label: l10n.commonEdit,
                    icon: Icons.edit_outlined,
                    variant: AppButtonVariant.text,
                    onPressed: () => setState(() => isEditingName = true),
                  ),
                ),
              GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: Prefs().bookCoverWidth,
                  childAspectRatio: AppBookshelfTokens.folderDialogAspectRatio,
                  crossAxisSpacing: AppBookshelfTokens.folderDialogSpacing,
                  mainAxisSpacing: AppBookshelfTokens.folderDialogSpacing,
                ),
                itemCount: books.length,
                itemBuilder: (context, index) => Stack(
                  children: [
                    BookItem(book: books[index]),
                    if (isEditing)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: AppIconButton(
                          semanticLabel: l10n.commonRemove,
                          tooltip: l10n.commonRemove,
                          variant: AppButtonVariant.danger,
                          onPressed: () {
                            ref
                                .read(bookListProvider.notifier)
                                .removeFromGroup(books[index]);
                            setState(() {
                              books.removeAt(index);
                              if (books.isEmpty) Navigator.pop(context);
                            });
                          },
                          child: const Icon(
                            Icons.remove_circle,
                            size: AppBookshelfTokens.folderRemoveIconSize,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppButton(
          label: l10n.commonDissolve,
          variant: AppButtonVariant.outlined,
          onPressed: () {
            ref.read(bookListProvider.notifier).dissolveGroup(books);
            Navigator.pop(context);
          },
        ),
        AppButton(
          label: isEditing ? l10n.commonCancel : l10n.commonEdit,
          variant: AppButtonVariant.text,
          onPressed: () => setState(() => isEditing = !isEditing),
        ),
      ],
    );
  }
}
