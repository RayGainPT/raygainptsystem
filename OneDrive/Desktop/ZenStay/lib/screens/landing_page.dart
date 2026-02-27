import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({Key? key}) : super(key: key);

  Color get _primary => const Color(0xFF008080);

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white.withOpacity(0.9),
        centerTitle: false,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [Color(0xFF008080), Color(0xFF14B8A6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                'Z',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'ZenStay',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade900,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.go('/login'),
            child: Text(
              'Log in',
              style: GoogleFonts.poppins(
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ElevatedButton(
              onPressed: () => context.go('/owner'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: Text(
                'List your property',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeroSection(context, isMobile),
                    const SizedBox(height: 32),
                    _buildHostSection(context, isMobile),
                    const SizedBox(height: 32),
                    _buildFeaturedSection(context, maxWidth),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context, bool isMobile) {
    return Stack(
      children: [
        Container(
          height: isMobile ? 420 : 520,
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: NetworkImage(
                'https://images.pexels.com/photos/258154/pexels-photo-258154.jpeg?auto=compress&cs=tinysrgb&w=1600',
              ),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Container(
          height: isMobile ? 420 : 520,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.45),
                Colors.black.withOpacity(0.15),
                Colors.white.withOpacity(0.0),
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 32,
              vertical: isMobile ? 32 : 48,
            ),
            child: Align(
              alignment:
                  isMobile ? Alignment.topLeft : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Your Private Escape,\nManaged with Zen.',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: isMobile ? 30 : 40,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Discover handpicked stays with dynamic pricing, verified guests, '
                      'and secure deposits – whether you are booking a weekend getaway '
                      'or listing your own property.',
                      style: GoogleFonts.poppins(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildSearchBar(context, isMobile),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context, bool isMobile) {
    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
        ),
        child: isMobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SearchField(
                    label: 'Location',
                    hint: 'Where are you going?',
                    icon: Icons.location_on_outlined,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _SearchField(
                          label: 'Dates',
                          hint: 'Add dates',
                          icon: Icons.calendar_today_outlined,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SearchField(
                          label: 'Guests',
                          hint: 'Add guests',
                          icon: Icons.person_outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () => context.go('/euroescape'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: Text(
                        'Search stays',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _SearchField(
                      label: 'Location',
                      hint: 'Try “Tagaytay” or “Batangas”',
                      icon: Icons.location_on_outlined,
                    ),
                  ),
                  const VerticalDivider(width: 24, thickness: 0.8),
                  Expanded(
                    flex: 2,
                    child: _SearchField(
                      label: 'Dates',
                      hint: 'Add dates',
                      icon: Icons.calendar_today_outlined,
                    ),
                  ),
                  const VerticalDivider(width: 24, thickness: 0.8),
                  Expanded(
                    flex: 2,
                    child: _SearchField(
                      label: 'Guests',
                      hint: 'Add guests',
                      icon: Icons.person_outline,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () => context.go('/euroescape'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: Text(
                        'Search',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHostSection(BuildContext context, bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Earn more with ZenStay.',
                      style: GoogleFonts.poppins(
                        fontSize: isMobile ? 22 : 26,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Turn your private escape into a steady income stream with automated '
                      'pricing, verified guests, and smart protection on every booking.',
                      style: GoogleFonts.poppins(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isMobile) ...[
                const SizedBox(width: 24),
                ElevatedButton(
                  onPressed: () => context.go('/login'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 12),
                  ),
                  child: Text(
                    'List your property',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 800;
              final children = [
                _HostFeatureCard(
                  icon: Icons.timeline_outlined,
                  title: 'Dynamic Rates',
                  description:
                      'Weekend and holiday pricing that updates automatically so you never undercharge.',
                ),
                _HostFeatureCard(
                  icon: Icons.verified_user_outlined,
                  title: 'Verified Guests',
                  description:
                      'Built-in ID and payment verification, so you know exactly who is checking in.',
                ),
                _HostFeatureCard(
                  icon: Icons.shield_outlined,
                  title: 'Zero-Leakage',
                  description:
                      'Security deposits and fees are tracked in one place to protect your revenue.',
                ),
              ];
              if (isNarrow) {
                return Column(
                  children: [
                    for (final c in children) ...[
                      c,
                      const SizedBox(height: 12),
                    ]
                  ],
                );
              } else {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children
                      .map((c) => Expanded(child: Padding(
                            padding: const EdgeInsets.only(right: 12.0),
                            child: c,
                          )))
                      .toList(),
                );
              }
            },
          ),
          if (isMobile) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.go('/login'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                child: Text(
                  'List your property',
                  style: GoogleFonts.poppins(
                    color: _primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeaturedSection(BuildContext context, double maxWidth) {
    final properties = [
      const _FeaturedProperty(
        slug: 'euroescape',
        name: 'Euroescape',
        location: 'Tagaytay, Philippines',
        pricePerNight: 2490,
        rating: 4.9,
        imageUrl:
            'https://images.pexels.com/photos/258154/pexels-photo-258154.jpeg?auto=compress&cs=tinysrgb&w=1200',
      ),
      const _FeaturedProperty(
        slug: 'sunset-villa',
        name: 'Sunset Villa',
        location: 'Batangas, Philippines',
        pricePerNight: 3290,
        rating: 4.8,
        imageUrl:
            'https://images.pexels.com/photos/261102/pexels-photo-261102.jpeg?auto=compress&cs=tinysrgb&w=1200',
      ),
      const _FeaturedProperty(
        slug: 'island-cove',
        name: 'Island Cove Retreat',
        location: 'Palawan, Philippines',
        pricePerNight: 4590,
        rating: 5.0,
        imageUrl:
            'https://images.pexels.com/photos/258154/pexels-photo-258154.jpeg?auto=compress&cs=tinysrgb&w=1200',
      ),
    ];

    int crossAxisCount = 3;
    if (maxWidth < 700) {
      crossAxisCount = 1;
    } else if (maxWidth < 1000) {
      crossAxisCount = 2;
    } else {
      crossAxisCount = 3;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Featured stays',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A peek at what your guests will see when they book through ZenStay.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: properties.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.9,
            ),
            itemBuilder: (context, index) {
              final prop = properties[index];
              return _FeaturedCard(
                property: prop,
                primaryColor: _primary,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;

  const _SearchField({
    Key? key,
    required this.label,
    required this.hint,
    required this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade700),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                hint,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HostFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _HostFeatureCard({
    Key? key,
    required this.icon,
    required this.title,
    required this.description,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2F2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF008080)),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturedProperty {
  final String slug;
  final String name;
  final String location;
  final double pricePerNight;
  final double rating;
  final String imageUrl;

  const _FeaturedProperty({
    required this.slug,
    required this.name,
    required this.location,
    required this.pricePerNight,
    required this.rating,
    required this.imageUrl,
  });
}

class _FeaturedCard extends StatelessWidget {
  final _FeaturedProperty property;
  final Color primaryColor;

  const _FeaturedCard({
    Key? key,
    required this.property,
    required this.primaryColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/${property.slug}'),
      borderRadius: BorderRadius.circular(16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.network(
                      property.imageUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(6),
                      child: const Icon(
                        Icons.favorite_border,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          property.name,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.star,
                              size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            property.rating.toStringAsFixed(1),
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    property.location,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '₱${property.pricePerNight.toStringAsFixed(0)} / night',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => context.go('/${property.slug}'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: primaryColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                      ),
                      child: Text(
                        'Book now',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: primaryColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

