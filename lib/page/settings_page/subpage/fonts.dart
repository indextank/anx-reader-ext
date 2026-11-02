import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/fonts.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';

class FontsSettingPage extends ConsumerWidget {
  const FontsSettingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontList = ref.watch(fontsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).downloadFonts)),
      body: AppSafeArea(
        top: false,
        child: AppAsyncValue<List<RemoteFontModel>>(
          value: fontList,
          isEmpty: (fonts) => fonts.isEmpty,
          emptyBuilder: (context) => AppEmptyState(
            title: L10n.of(context).fontNoAvailableFonts,
            message: L10n.of(context).downloadFonts,
            actionLabel: L10n.of(context).commonRefresh,
            onAction: () => _refresh(ref),
          ),
          onRetry: () => _refresh(ref),
          errorBuilder: (context, error, stackTrace) => AppErrorState(
            title: L10n.of(context).fontFailedToLoadFonts,
            onRetry: () => _refresh(ref),
          ),
          dataBuilder: (context, fonts) => ListView.builder(
            itemCount: fonts.length,
            itemBuilder: (context, index) => _FontCard(font: fonts[index]),
          ),
        ),
      ),
    );
  }

  static Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(fontsProvider);
    await ref.read(fontsProvider.future);
  }
}

class _FontCard extends ConsumerWidget {
  const _FontCard({required this.font});

  final RemoteFontModel font;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return AppCard(
      margin: AppSpacing.all8,
      padding: AppSpacing.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (font.preview.isNotEmpty) ...[
            _FontPreview(url: 'https://fonts.anxcye.com/${font.preview}'),
            const Divider(),
          ],
          Padding(
            padding: AppSpacing.all16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(font.name, style: Theme.of(context).textTheme.titleMedium),
                SizedBox(height: AppSpacing.tokens.s8),
                Text(font.desc),
                SizedBox(height: AppSpacing.tokens.s8),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.tokens.s8,
                  runSpacing: AppSpacing.tokens.s8,
                  children: [
                    AppButton(
                      label: l10n.fontOfficialWebsite,
                      icon: Icons.link,
                      variant: AppButtonVariant.text,
                      onPressed: () {
                        launchUrlString(
                          font.official,
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                    AppButton(
                      label: font.license.name,
                      icon: Icons.link,
                      variant: AppButtonVariant.text,
                      onPressed: () {
                        launchUrlString(
                          font.license.url,
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                  ],
                ),
                SizedBox(height: AppSpacing.tokens.s16),
                _DownloadButton(font: font),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FontPreview extends StatefulWidget {
  const _FontPreview({required this.url});

  final String url;

  @override
  State<_FontPreview> createState() => _FontPreviewState();
}

class _FontPreviewState extends State<_FontPreview> {
  int _attempt = 0;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      key: ValueKey(_attempt),
      color: Theme.of(context).colorScheme.onSurface,
      imageUrl: widget.url,
      width: MediaQuery.of(context).size.width,
      fit: BoxFit.cover,
      placeholder: (context, url) => const Center(child: AppLoadingIndicator()),
      errorWidget: (context, url, error) => AppInlineFeedback(
        message: L10n.of(context).commonLoadFailed,
        onRetry: () => setState(() => _attempt++),
      ),
    );
  }
}

class _DownloadButton extends ConsumerWidget {
  const _DownloadButton({required this.font});

  final RemoteFontModel font;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final downloadState = ref.watch(fontDownloadsProvider)[font.id];
    final fontDownloads = ref.read(fontDownloadsProvider.notifier);
    final isAllFilesDownloaded =
        font.files.every((file) => fontDownloads.isDownloaded(font.id, file));

    if (isAllFilesDownloaded) {
      return AppButton(
        label: l10n.fontDownloaded,
        icon: Icons.check,
        enabled: false,
      );
    }

    if (downloadState != null) {
      switch (downloadState.status) {
        case DownloadStatus.downloading:
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: downloadState.progress),
              SizedBox(height: AppSpacing.tokens.s8),
              Text(
                '${l10n.fontDownloading((downloadState.progress * 100).toStringAsFixed(1))}%',
              ),
              Wrap(
                spacing: AppSpacing.tokens.s8,
                runSpacing: AppSpacing.tokens.s8,
                children: [
                  AppButton(
                    label: l10n.commonPause,
                    icon: Icons.pause,
                    variant: AppButtonVariant.text,
                    onPressed: () => fontDownloads.pauseDownload(font.id),
                  ),
                  AppButton(
                    label: l10n.commonCancel,
                    icon: Icons.cancel,
                    variant: AppButtonVariant.text,
                    onPressed: () => fontDownloads.cancelDownload(font.id),
                  ),
                ],
              ),
            ],
          );
        case DownloadStatus.paused:
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l10n.fontCancelled((downloadState.progress * 100).toStringAsFixed(1))}%',
              ),
              Wrap(
                spacing: AppSpacing.tokens.s8,
                runSpacing: AppSpacing.tokens.s8,
                children: [
                  AppButton(
                    label: l10n.commonResume,
                    icon: Icons.play_arrow,
                    variant: AppButtonVariant.text,
                    onPressed: () => fontDownloads.resumeDownload(font),
                  ),
                  AppButton(
                    label: l10n.commonCancel,
                    icon: Icons.cancel,
                    variant: AppButtonVariant.text,
                    onPressed: () => fontDownloads.cancelDownload(font.id),
                  ),
                ],
              ),
            ],
          );
        case DownloadStatus.failed:
          return AppInlineFeedback(
            message: l10n.commonDownloadFailed,
            onRetry: () => fontDownloads.startDownload(font),
          );
        case DownloadStatus.none:
        case DownloadStatus.completed:
          break;
      }
    }

    return AppButton(
      label: l10n.commonDownload,
      icon: Icons.download,
      onPressed: () => fontDownloads.startDownload(font),
    );
  }
}
