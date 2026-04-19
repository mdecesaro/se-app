import 'package:flutter/material.dart';
import '../models/athlete.dart';

class MeScreen extends StatelessWidget {
  final Athlete? athlete;
  const MeScreen({super.key, this.athlete});

  @override
  Widget build(BuildContext context) {
    if (athlete == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Me",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            
            // Header with Profile Image and Name
            Center(
              child: Column(
                children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.amber, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.2),
                          blurRadius: 15,
                          spreadRadius: 5,
                        )
                      ],
                      image: athlete!.profile.isNotEmpty
                          ? DecorationImage(
                              image: MemoryImage(athlete!.profile),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: athlete!.profile.isEmpty
                        ? const Icon(Icons.person, size: 80, color: Colors.white24)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    athlete!.name.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Text(
                    athlete!.position.toUpperCase(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade300,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Personal Information Card
            const Text(
              "PERSONAL INFORMATION",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF3D3D3D), // Matching "Heller" theme
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  _buildInfoRow(Icons.person_outline, "Gender", athlete!.gender),
                  const Divider(color: Colors.white10, height: 24),
                  _buildInfoRow(Icons.public, "Country", athlete!.country),
                  const Divider(color: Colors.white10, height: 24),
                  _buildInfoRow(Icons.cake_outlined, "Birth Date", _formatDate(athlete!.birth)),
                  const Divider(color: Colors.white10, height: 24),
                  _buildInfoRow(Icons.settings_accessibility, "Dominant Foot", athlete!.dominantFoot),
                  const Divider(color: Colors.white10, height: 24),
                  _buildInfoRow(Icons.numbers, "Preferred Number", athlete!.preferredNumber.toString()),
                  const Divider(color: Colors.white10, height: 24),
                  _buildInfoRow(Icons.sports_soccer, "Position", athlete!.position),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Placeholder for future cards (Achievements)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.emoji_events_outlined, color: Colors.white24),
                  SizedBox(width: 16),
                  Text(
                    "Achievements & Medals coming soon...",
                    style: TextStyle(color: Colors.white24),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String date) {
    try {
      final parts = date.split('-');
      if (parts.length == 3) {
        return "${parts[2]}/${parts[1]}/${parts[0]}";
      }
      return date;
    } catch (e) {
      return date;
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFF6D00), size: 20),
        const SizedBox(width: 16),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class FifaCard extends StatelessWidget {
  final Athlete athlete;
  final bool isCompact;

  const FifaCard({
    super.key, 
    required this.athlete, 
    this.isCompact = false,
  });

  Widget _buildSidebarGradientDivider(double height) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: height / 2),
      height: 1.5,
      width: 150,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            Colors.amber.shade300.withOpacity(0.5),
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // For sidebar, we want it even narrower to fit the 210px width
    final double cardWidth = isCompact ? 170 : 300;
    final double ratingSize = isCompact ? 32 : 54;
    final double nameSize = isCompact ? 12 : 22;
    final double statValueSize = isCompact ? 16 : 24;
    final double statLabelSize = isCompact ? 7 : 10;
    final double imageHeight = isCompact ? 80 : 180;

    return Container(
      width: cardWidth,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.amber.shade600,
            Colors.amber.shade800,
            Colors.black,
          ],
          stops: const [0.0, 0.3, 1.0],
        ),
        borderRadius: BorderRadius.circular(isCompact ? 15 : 20),
        border: Border.all(color: Colors.amber.shade300, width: isCompact ? 1.5 : 2),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.2),
            blurRadius: isCompact ? 10 : 20,
            spreadRadius: isCompact ? 2 : 5,
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isCompact ? 15 : 20),
        child: Stack(
          children: [
            Positioned(
              top: -10,
              left: -10,
              child: Opacity(
                opacity: 0.1,
                child: Icon(Icons.shield, size: isCompact ? 200 : 300, color: Colors.white),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(isCompact ? 12.0 : 20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          Text(
                            "70",
                            style: TextStyle(
                              fontSize: ratingSize,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                          Text(
                            athlete.position.toUpperCase().substring(0, 3),
                            style: TextStyle(
                              fontSize: isCompact ? 12 : 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                            ),
                          ),
                          SizedBox(height: isCompact ? 4 : 12),
                          Icon(Icons.public, color: Colors.white, size: isCompact ? 16 : 24),
                        ],
                      ),
                      const Spacer(),
                      Expanded(
                        child: Container(
                          height: imageHeight,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            image: athlete.profile.isNotEmpty
                                ? DecorationImage(
                                    image: MemoryImage(athlete.profile),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: athlete.profile.isEmpty
                              ? Icon(Icons.person, size: isCompact ? 60 : 100, color: Colors.white24)
                              : null,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isCompact ? 8 : 15),
                  Text(
                    athlete.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: nameSize,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  _buildSidebarGradientDivider(isCompact ? 12 : 20),

                  Text(
                    "MOTOR SKILL SCORE",
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: isCompact ? 7 : 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: isCompact ? 1 : 2,
                    ),
                  ),
                  SizedBox(height: isCompact ? 8 : 15),
                  // Stats Grid
                  _buildStatsRow("Reaction", 78, "Agility", 72, isCompact),
                  SizedBox(height: isCompact ? 8 : 12),
                  _buildStatsRow("Balance", 61, "Decision", 69, isCompact),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(String l1, int v1, String l2, int v2, bool compact) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildFifaStat(l1, v1, compact),
        _buildFifaStat(l2, v2, compact),
      ],
    );
  }

  Widget _buildFifaStat(String label, int value, bool compact) {
    return SizedBox(
      width: compact ? 70 : 100,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white60,
              fontSize: compact ? 7 : 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
            maxLines: 1,
          ),
          SizedBox(height: compact ? 2 : 4),
          Text(
            "$value",
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 16 : 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
