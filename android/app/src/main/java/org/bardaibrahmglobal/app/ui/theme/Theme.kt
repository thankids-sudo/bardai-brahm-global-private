package org.bardaibrahmglobal.app.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

val Navy = Color(0xFF1B2A4A)
val NavyLight = Color(0xFF2C4170)
val Gold = Color(0xFFC9A227)
val GoldSoft = Color(0xFFF3E3B0)
val BanyanGreen = Color(0xFF2E6B34)
val GreenSoft = Color(0xFFD5E8D4)
val WarmWhite = Color(0xFFFFF8EC)
val Ink = Color(0xFF1C1B1F)

private val Colors = lightColorScheme(
    primary = Navy,
    onPrimary = WarmWhite,
    primaryContainer = NavyLight,
    onPrimaryContainer = WarmWhite,
    secondary = Gold,
    onSecondary = Navy,
    secondaryContainer = GoldSoft,
    onSecondaryContainer = Navy,
    tertiary = BanyanGreen,
    onTertiary = WarmWhite,
    tertiaryContainer = GreenSoft,
    onTertiaryContainer = Ink,
    background = WarmWhite,
    onBackground = Ink,
    surface = WarmWhite,
    onSurface = Ink,
    surfaceVariant = Color(0xFFF4ECDC),
    onSurfaceVariant = Color(0xFF4A4639),
)

// Gujarati script has tall matras and conjuncts, so line heights are generous.
// Default system sans serif resolves to Noto Sans Gujarati on Android.
private val Base = FontFamily.SansSerif
private val AppTypography = Typography(
    headlineMedium = TextStyle(fontFamily = Base, fontWeight = FontWeight.SemiBold, fontSize = 26.sp, lineHeight = 36.sp),
    titleLarge = TextStyle(fontFamily = Base, fontWeight = FontWeight.SemiBold, fontSize = 21.sp, lineHeight = 30.sp),
    titleMedium = TextStyle(fontFamily = Base, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, lineHeight = 26.sp),
    bodyLarge = TextStyle(fontFamily = Base, fontSize = 16.sp, lineHeight = 26.sp),
    bodyMedium = TextStyle(fontFamily = Base, fontSize = 15.sp, lineHeight = 24.sp),
    labelLarge = TextStyle(fontFamily = Base, fontWeight = FontWeight.Medium, fontSize = 15.sp, lineHeight = 22.sp),
    labelMedium = TextStyle(fontFamily = Base, fontWeight = FontWeight.Medium, fontSize = 12.sp, lineHeight = 18.sp),
)

@Composable
fun BardaiTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = Colors, typography = AppTypography, content = content)
}
