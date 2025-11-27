import 'package:flutter/material.dart';
import '../theme.dart';

class FollowCounts extends StatelessWidget {
  final int followerCount;
  final int followingCount;

  const FollowCounts({
    super.key,
    required this.followerCount,
    required this.followingCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FollowCard(
            label: 'Follower',
            value: followerCount,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FollowCard(
            label: 'Seguiti',
            value: followingCount,
          ),
        ),
      ],
    );
  }
}

class _FollowCard extends StatelessWidget {
  final String label;
  final int value;

  const _FollowCard({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [
            Color.fromRGBO(255, 255, 255, 0.08),
            Color.fromRGBO(255, 255, 255, 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: kLineColor.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: kMutedColor,
              fontSize: 11,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: const TextStyle(
              color: kFgColor,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
