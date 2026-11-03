enum AiPanelPositionEnum {
  right('right'),
  bottom('bottom'),
  popup('popup');

  final String code;

  const AiPanelPositionEnum(this.code);

  static AiPanelPositionEnum fromCode(
    String? code, {
    AiPanelPositionEnum fallback = AiPanelPositionEnum.right,
  }) {
    switch (code) {
      case 'right':
        return AiPanelPositionEnum.right;
      case 'bottom':
        return AiPanelPositionEnum.bottom;
      case 'popup':
        return AiPanelPositionEnum.popup;
      default:
        return fallback;
    }
  }
}
