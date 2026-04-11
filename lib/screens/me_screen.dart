import 'package:flutter/material.dart';
import '../models/athlete.dart';
import '../services/database_service.dart';

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
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: colorScheme.primary,
                    backgroundImage: athlete!.profile.isNotEmpty 
                        ? MemoryImage(athlete!.profile) 
                        : null,
                    child: athlete!.profile.isEmpty 
                        ? const Icon(Icons.person, size: 60, color: Colors.white) 
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    athlete!.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    athlete!.position,
                    style: TextStyle(
                      fontSize: 16,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
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
