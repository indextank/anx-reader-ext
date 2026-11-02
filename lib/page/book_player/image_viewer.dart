import 'dart:convert';
import 'dart:typed_data';

import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/save_image_to_path.dart';
import 'package:anx_reader/utils/save_img.dart';
import 'package:anx_reader/utils/share_file.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

class ImageViewer extends StatefulWidget {
  const ImageViewer({
    super.key,
    required this.image,
    required this.bookName,
    this.onDownload,
    this.onShare,
  });

  final String image;
  final String bookName;
  final Future<void> Function(
    Uint8List bytes,
    String type,
    String bookName,
  )? onDownload;
  final Future<void> Function(String image, String bookName)? onShare;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

enum _ImageAction { download, share }

class _ImageViewerState extends State<ImageViewer> {
  late PhotoViewController _controller;
  _ImageAction? _pendingAction;
  _ImageAction? _failedAction;
  int _imageRevision = 0;

  @override
  void initState() {
    super.initState();
    _controller = PhotoViewController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleScroll(PointerScrollEvent event) {
    final scrollDelta = event.scrollDelta.dy;
    final currentScale = _controller.scale ?? 1.0;
    final scaleFactor = scrollDelta > 0 ? 0.95 : 1.05;
    _controller.scale = currentScale * scaleFactor;
  }

  (Uint8List, String)? _decodeImage() {
    try {
      final parts = widget.image.split(',');
      if (parts.length != 2) return null;
      final bytes = base64Decode(parts[1]);
      if (bytes.isEmpty) return null;
      final type = parts[0].split('/')[1].split(';')[0];
      return (bytes, type);
    } catch (error) {
      AnxLog.severe('Error decoding image: $error');
      return null;
    }
  }

  Future<void> _runAction(
    _ImageAction action,
    Uint8List bytes,
    String type,
  ) async {
    if (_pendingAction != null) return;
    setState(() {
      _pendingAction = action;
      _failedAction = null;
    });
    try {
      if (action == _ImageAction.download) {
        final download = widget.onDownload;
        if (download != null) {
          await download(bytes, type, widget.bookName);
        } else {
          await SaveImg.downloadImg(bytes, type, widget.bookName);
        }
      } else {
        final share = widget.onShare;
        if (share != null) {
          await share(widget.image, widget.bookName);
        } else {
          final path = await saveB64ImageToPath(
            widget.image,
            (await getAnxTempDir()).path,
            'AnxReader_${widget.bookName}',
          );
          await shareFile(filePath: path);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _failedAction = action);
    } finally {
      if (mounted) setState(() => _pendingAction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final decoded = _decodeImage();
    if (decoded == null) {
      return const ColoredBox(
        color: AppReadingTokens.imageBackground,
        child: AppErrorState(icon: Icons.broken_image_outlined),
      );
    }

    final (imageBytes, imgType) = decoded;
    final l10n = L10n.of(context);
    final failedAction = _failedAction;
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) _handleScroll(event);
      },
      child: ColoredBox(
        color: AppReadingTokens.imageBackground,
        child: Stack(
          children: [
            PhotoView(
              key: ValueKey(_imageRevision),
              imageProvider: MemoryImage(imageBytes),
              controller: _controller,
              backgroundDecoration: const BoxDecoration(
                color: AppReadingTokens.imageBackground,
              ),
              loadingBuilder: (context, event) => const Center(
                child: AppLoadingIndicator(),
              ),
              errorBuilder: (context, error, stackTrace) => AppErrorState(
                icon: Icons.broken_image_outlined,
                onRetry: () async {
                  setState(() => _imageRevision++);
                },
              ),
              minScale: PhotoViewComputedScale.contained * 0.8,
              maxScale: PhotoViewComputedScale.covered * 3,
            ),
            Positioned.fill(
              child: AppSafeArea(
                avoidViewInsets: false,
                child: Padding(
                  padding: AppReadingTokens.contentPadding,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          AppIconButton(
                            tooltip: l10n.commonCancel,
                            onPressed: () => Navigator.maybePop(context),
                            child: const Icon(
                              Icons.close,
                              color: AppReadingTokens.imageForeground,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (failedAction != null)
                        AppInlineFeedback(
                          message: l10n.commonActionFailed,
                          onRetry: () => _runAction(
                            failedAction,
                            imageBytes,
                            imgType,
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AppIconButton(
                            tooltip: l10n.commonDownload,
                            isLoading: _pendingAction == _ImageAction.download,
                            enabled: _pendingAction == null,
                            onPressed: () => _runAction(
                              _ImageAction.download,
                              imageBytes,
                              imgType,
                            ),
                            child: const Icon(
                              Icons.download,
                              color: AppReadingTokens.imageForeground,
                            ),
                          ),
                          AppIconButton(
                            tooltip: l10n.contextMenuShare,
                            isLoading: _pendingAction == _ImageAction.share,
                            enabled: _pendingAction == null,
                            onPressed: () => _runAction(
                              _ImageAction.share,
                              imageBytes,
                              imgType,
                            ),
                            child: const Icon(
                              Icons.share,
                              color: AppReadingTokens.imageForeground,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
