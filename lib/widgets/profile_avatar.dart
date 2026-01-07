import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme.dart';

/// Widget riutilizzabile per mostrare l'avatar del profilo utente.
/// Mostra l'immagine profilo se disponibile, altrimenti mostra le iniziali.
class ProfileAvatar extends StatelessWidget {
  final String? profileImageUrl;
  final String userTag;
  final double size;
  final double borderWidth;
  final bool showGradientBorder;
  final VoidCallback? onTap;

  const ProfileAvatar({
    super.key,
    required this.profileImageUrl,
    required this.userTag,
    this.size = 48,
    this.borderWidth = 2,
    this.showGradientBorder = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = profileImageUrl != null && profileImageUrl!.isNotEmpty;

    Widget avatarContent = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1A1A1A),
        border: Border.all(
          color: const Color(0xFF2A2A2A),
          width: borderWidth,
        ),
      ),
      child: hasImage
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: profileImageUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => Center(
                  child: SizedBox(
                    width: size * 0.4,
                    height: size * 0.4,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(kBrandColor),
                      strokeWidth: 2,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Center(
                  child: Text(
                    userTag,
                    style: TextStyle(
                      fontSize: size * 0.33,
                      fontWeight: FontWeight.w900,
                      color: kBrandColor,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                userTag,
                style: TextStyle(
                  fontSize: size * 0.33,
                  fontWeight: FontWeight.w900,
                  color: kBrandColor,
                  letterSpacing: 1,
                ),
              ),
            ),
    );

    if (showGradientBorder) {
      avatarContent = Container(
        padding: EdgeInsets.all(borderWidth + 1),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              kBrandColor.withAlpha(120),
              kPulseColor.withAlpha(80),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: avatarContent,
      );
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: avatarContent,
      );
    }

    return avatarContent;
  }
}

/// Variante più piccola e semplice per le liste
class ProfileAvatarCompact extends StatelessWidget {
  final String? profileImageUrl;
  final String userTag;
  final double size;

  const ProfileAvatarCompact({
    super.key,
    required this.profileImageUrl,
    required this.userTag,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return ProfileAvatar(
      profileImageUrl: profileImageUrl,
      userTag: userTag,
      size: size,
      borderWidth: 1.5,
      showGradientBorder: false,
    );
  }
}
