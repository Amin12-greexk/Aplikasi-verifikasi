class IDCardData {
  final String rawValue;

  const IDCardData({required this.rawValue});

  factory IDCardData.fromQRString(String qrContent) {
    return IDCardData(rawValue: qrContent.trim());
  }
}
