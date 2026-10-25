class WebCouponDeal {
  const WebCouponDeal({
    required this.title,
    required this.merchant,
    required this.category,
    required this.url,
    required this.price,
    required this.discount,
    required this.description,
    required this.updatedAt,
  });

  final String title;
  final String merchant;
  final String category;
  final String url;
  final String price;
  final String discount;
  final String description;
  final DateTime? updatedAt;

  factory WebCouponDeal.fromJson(Map<String, Object?> json) {
    final category = json['category'] as Map<Object?, Object?>?;
    final updatedAt = json['updated_at'] as String?;
    return WebCouponDeal(
      title: json['title'] as String? ?? 'Untitled deal',
      merchant: json['merchant'] as String? ?? '',
      category: category?['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      price: json['price'] as String? ?? '',
      discount: json['discount'] as String? ?? '',
      description: json['useful_for'] as String? ?? '',
      updatedAt: updatedAt == null ? null : DateTime.tryParse(updatedAt),
    );
  }
}
