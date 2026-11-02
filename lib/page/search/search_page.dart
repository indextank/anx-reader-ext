import 'package:anx_reader/l10n/generated/L10n.dart';
import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/search_note_group.dart';
import 'package:anx_reader/providers/search.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/widgets/book_notes/book_note_tile.dart';
import 'package:anx_reader/widgets/bookshelf/book_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _controller.addListener(() {
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(searchQueryProvider.notifier).state = '';
      FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(AppSearchTokens.debounce, () {
      ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  void _clearQuery() {
    _debounce?.cancel();
    _controller.clear();
    ref.read(searchQueryProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final asyncResult = ref.watch(searchResultProvider);

    final appBar = AppBar(
      forceMaterialTransparency: true,
      titleSpacing: 0,
      title: Padding(
        padding: AppSearchTokens.appBarPadding,
        child: AppTextField(
          controller: _controller,
          focusNode: _focusNode,
          hintText: L10n.of(context).searchBooksOrNotes,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _controller.text.isEmpty
              ? null
              : AppIconButton(
                  icon: Icons.clear,
                  tooltip: L10n.of(context).close,
                  onPressed: _clearQuery,
                ),
          border: const OutlineInputBorder(borderRadius: AppRadius.border32),
          contentPadding: AppSearchTokens.inputPadding,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          onSubmitted: (value) {
            _debounce?.cancel();
            ref.read(searchQueryProvider.notifier).state = value;
          },
        ),
      ),
    );

    return Scaffold(
      appBar: appBar,
      body: AppSafeArea(
        top: false,
        child: asyncResult.when(
          data: (result) {
            if (query.trim().isEmpty) {
              return AppEmptyState(
                icon: Icons.search,
                message: L10n.of(context).startTypingToSearch,
              );
            }
            return SingleChildScrollView(
              padding: AppSearchTokens.bodyPadding,
              child: Column(
                spacing: AppSearchTokens.sectionSpacing,
                children: [
                  _SearchResult(
                    title: L10n.of(context).books,
                    empty: result.books.isEmpty,
                    child: _SearchBookResult(books: result.books),
                  ),
                  _SearchResult(
                    title: L10n.of(context).notes,
                    empty: result.noteGroups.isEmpty,
                    child: _SearchNoteResult(group: result.noteGroups),
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(child: AppLoadingIndicator()),
          error: (error, stack) => AppErrorState(
            onRetry: () async {
              ref.invalidate(searchResultProvider);
              await ref.read(searchResultProvider.future);
            },
          ),
        ),
      ),
    );
  }
}

class _SearchResult extends ConsumerWidget {
  const _SearchResult({
    required this.title,
    required this.child,
    required this.empty,
  });

  final String title;
  final Widget child;
  final bool empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleLarge!
              .copyWith(fontWeight: FontWeight.bold),
        ),
        SizedBox(height: AppSearchTokens.titleSpacing),
        SizedBox(
          width: double.infinity,
          child: AppCard(
            padding: AppSearchTokens.cardPadding,
            child: empty
                ? AppEmptyState(title: L10n.of(context).nothingHere)
                : child,
          ),
        ),
      ],
    );
  }
}

class _SearchBookResult extends ConsumerWidget {
  const _SearchBookResult({required this.books});

  final List<Book> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMany = books.length > AppSearchTokens.manyBooksThreshold;
    final manyFactor = isMany ? 2 : 1;

    final coverWidth = Prefs().bookCoverWidth / AppSearchTokens.coverScale;
    final tileHeight = coverWidth * AppSearchTokens.coverAspectRatio +
        AppSearchTokens.tileExtraHeight;
    final booksSectionHeight =
        tileHeight * manyFactor + AppSearchTokens.sectionExtraHeight;

    return SizedBox(
      height: booksSectionHeight,
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: manyFactor,
          mainAxisSpacing: AppSearchTokens.gridSpacing,
          crossAxisSpacing: AppSearchTokens.gridSpacing,
          childAspectRatio: AppSearchTokens.coverAspectRatio,
        ),
        itemBuilder: (context, index) {
          final book = books[index];
          return BookItem(book: book);
        },
        itemCount: books.length,
        physics: const BouncingScrollPhysics(),
        padding: AppSearchTokens.gridPadding,
      ),
    );
  }
}

class _SearchNoteResult extends ConsumerWidget {
  const _SearchNoteResult({required this.group});

  final List<SearchNoteGroup> group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      spacing: AppSearchTokens.noteGroupSpacing,
      children: group.map((item) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.book.title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            SizedBox(height: AppSearchTokens.noteTitleSpacing),
            AppCard(
              borderRadius: AppRadius.border16,
              color: Theme.of(context).scaffoldBackgroundColor,
              padding: AppSpacing.zero,
              child: Column(
                children: item.notes.map((note) {
                  return Padding(
                    padding: AppSearchTokens.notePadding,
                    child: BookNoteTile(
                      backgroundColor:
                          Theme.of(context).scaffoldBackgroundColor,
                      note: note,
                      margin: AppSpacing.zero,
                      onTap: () {
                        pushToReadingPage(ref, context, item.book,
                            cfi: note.cfi);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}
