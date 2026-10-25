class Offer {
  const Offer({
    required this.id,
    required this.brand,
    required this.title,
    required this.description,
    this.originalMessage = '',
    this.captureId,
    required this.code,
    required this.category,
    required this.source,
    required this.validUntil,
    required this.savedAt,
    this.isFavorite = false,
    this.isArchived = false,
    required this.colorValue,
    required this.iconKey,
  });

  final String id;
  final String brand;
  final String title;
  final String description;
  final String originalMessage;
  final String? captureId;
  final String code;
  final String category;
  final String source;
  final DateTime validUntil;
  final DateTime savedAt;
  final bool isFavorite;
  final bool isArchived;
  final int colorValue;
  final String iconKey;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'brand': brand,
      'title': title,
      'description': description,
      'originalMessage': originalMessage,
      if (captureId != null) 'captureId': captureId,
      'code': code,
      'category': category,
      'source': source,
      'validUntil': validUntil.toIso8601String(),
      'savedAt': savedAt.toIso8601String(),
      'isFavorite': isFavorite,
      'isArchived': isArchived,
      'colorValue': colorValue,
      'iconKey': iconKey,
    };
  }

  factory Offer.fromJson(Map<String, Object?> json) {
    return Offer(
      id: json['id']! as String,
      brand: json['brand']! as String,
      title: json['title']! as String,
      description: json['description']! as String,
      originalMessage: json['originalMessage'] as String? ?? '',
      captureId: json['captureId'] as String?,
      code: json['code']! as String,
      category: json['category']! as String,
      source: json['source']! as String,
      validUntil: DateTime.parse(json['validUntil']! as String),
      savedAt: DateTime.parse(json['savedAt']! as String),
      isFavorite: json['isFavorite'] as bool? ?? false,
      isArchived: json['isArchived'] as bool? ?? false,
      colorValue: (json['colorValue'] as num).toInt(),
      iconKey: json['iconKey']! as String,
    );
  }

  Offer copyWith({
    String? id,
    String? brand,
    String? title,
    String? description,
    String? originalMessage,
    String? captureId,
    String? code,
    String? category,
    String? source,
    DateTime? validUntil,
    DateTime? savedAt,
    bool? isFavorite,
    bool? isArchived,
    int? colorValue,
    String? iconKey,
  }) {
    return Offer(
      id: id ?? this.id,
      brand: brand ?? this.brand,
      title: title ?? this.title,
      description: description ?? this.description,
      originalMessage: originalMessage ?? this.originalMessage,
      captureId: captureId ?? this.captureId,
      code: code ?? this.code,
      category: category ?? this.category,
      source: source ?? this.source,
      validUntil: validUntil ?? this.validUntil,
      savedAt: savedAt ?? this.savedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      isArchived: isArchived ?? this.isArchived,
      colorValue: colorValue ?? this.colorValue,
      iconKey: iconKey ?? this.iconKey,
    );
  }
}

List<Offer> buildSampleOffers({DateTime? now}) {
  final baseDate = now ?? DateTime.now();

  return [
    Offer(
      id: 'sample-nike-25',
      brand: 'Nike',
      title: '25% off running shoes',
      description: 'Selected running shoes.',
      originalMessage:
          'Nike: Save 25% on selected running shoes with code RUN25.',
      code: 'RUN25',
      category: 'Fashion',
      source: 'OffersBucket',
      validUntil: baseDate.add(const Duration(days: 14)),
      savedAt: baseDate.subtract(const Duration(days: 1)),
      colorValue: 0xFF111111,
      iconKey: 'directions_run',
    ),
    Offer(
      id: 'sample-starbucks-drink',
      brand: 'Starbucks',
      title: 'Free size upgrade',
      description: 'Upgrade any handcrafted drink.',
      originalMessage: 'Starbucks: Get a free size upgrade with code UPSIZE.',
      code: 'UPSIZE',
      category: 'Food & Drink',
      source: 'OffersBucket',
      validUntil: baseDate.add(const Duration(days: 7)),
      savedAt: baseDate.subtract(const Duration(days: 3)),
      colorValue: 0xFF00754A,
      iconKey: 'local_cafe',
      isFavorite: true,
    ),
    Offer(
      id: 'sample-amazon-shipping',
      brand: 'Amazon',
      title: 'Free shipping',
      description: 'Eligible orders only.',
      originalMessage:
          'Amazon: Free shipping on eligible orders with code SHIPFREE.',
      code: 'SHIPFREE',
      category: 'Shopping',
      source: 'OffersBucket',
      validUntil: baseDate.add(const Duration(days: 30)),
      savedAt: baseDate.subtract(const Duration(hours: 12)),
      colorValue: 0xFFFF9900,
      iconKey: 'local_shipping',
    ),
  ];
}

List<Offer> get sampleOffers => buildSampleOffers();
