class Property {
  final String propertyId;
  final String ownerId;
  final String slug;
  final String name;
  final String description;
  final Map<String, dynamic> pricingConfig;
  final List<String> externalCalendars;
  final Map<String, dynamic> settings;

  Property({
    required this.propertyId,
    required this.ownerId,
    required this.slug,
    required this.name,
    required this.description,
    required this.pricingConfig,
    required this.externalCalendars,
    required this.settings,
  });

  factory Property.fromMap(Map<String, dynamic> data, String id) {
    return Property(
      propertyId: id,
      ownerId: data['ownerId'] ?? '',
      slug: data['slug'] ?? '',
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      pricingConfig: Map<String, dynamic>.from(data['pricingConfig'] ?? {}),
      externalCalendars: List<String>.from(data['externalCalendars'] ?? []),
      settings: Map<String, dynamic>.from(data['settings'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'slug': slug,
      'name': name,
      'description': description,
      'pricingConfig': pricingConfig,
      'externalCalendars': externalCalendars,
      'settings': settings,
    };
  }
}
