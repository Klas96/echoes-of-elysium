import 'package:bonfire/bonfire.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:async';

/// Custom texture map component that uses a texture image and a mask image
/// for collision detection. Black pixels in the mask are walkable, white pixels are blocked.
class CustomTextureMap extends Component {
  final String texturePath;
  final String maskPath;
  ui.Image? textureImage;
  ui.Image? maskImage;
  ByteData? maskBytes;
  final Completer<void> assetsLoaded = Completer<void>();
  int _debugFrameCount = 0;
  late Vector2 position;
  late Vector2 size;

  CustomTextureMap({required this.texturePath, required this.maskPath}) {
    position = Vector2.zero();
    size = Vector2(3421, 4131); // updated after load from actual image size
    priority = -1000;
  }

  @override
  Future<void> onLoad() async {
    print('Loading texture map...');
    try {
      // Load images using Flutter's asset loading system
      final textureData = await rootBundle.load('assets/images/$texturePath');
      final maskData = await rootBundle.load('assets/images/$maskPath');
      
      print('Texture data loaded: ${textureData.lengthInBytes} bytes');
      print('Mask data loaded: ${maskData.lengthInBytes} bytes');
      
      final textureCodec = await ui.instantiateImageCodec(textureData.buffer.asUint8List());
      final maskCodec = await ui.instantiateImageCodec(maskData.buffer.asUint8List());
      
      final textureFrame = await textureCodec.getNextFrame();
      final maskFrame = await maskCodec.getNextFrame();
      
      textureImage = textureFrame.image;
      maskImage = maskFrame.image;
      maskBytes = await maskImage!.toByteData(format: ui.ImageByteFormat.rawRgba);
      size = Vector2(textureImage!.width.toDouble(), textureImage!.height.toDouble());
      assetsLoaded.complete();
      
      print('Mask loaded: ${maskImage!.width}x${maskImage!.height}, bytes: ${maskBytes!.lengthInBytes}');
      
      // Test a few pixels to see what values we get
      for (int i = 0; i < 10; i++) {
        final offset = i * 4;
        final r = maskBytes!.getUint8(offset);
        final g = maskBytes!.getUint8(offset+1);
        final b = maskBytes!.getUint8(offset+2);
        print('Sample pixel $i: RGB($r, $g, $b)');
      }
      
      // Test some pixels from different areas
      final testPositions = [
        Vector2(100, 100),
        Vector2(200, 200),
        Vector2(300, 300),
        Vector2(400, 400),
        Vector2(500, 500),
      ];
      
      for (final pos in testPositions) {
        final px = pos.x.clamp(0, maskImage!.width-1).toInt();
        final py = pos.y.clamp(0, maskImage!.height-1).toInt();
        final offset = (py * maskImage!.width + px) * 4;
        
        if (offset < maskBytes!.lengthInBytes) {
          final r = maskBytes!.getUint8(offset);
          final g = maskBytes!.getUint8(offset+1);
          final b = maskBytes!.getUint8(offset+2);
          print('Test position ($px, $py): RGB($r, $g, $b)');
        }
      }
    } catch (e) {
      print('Error loading mask: $e');
    }
  }

  @override
  void render(Canvas canvas) {
    if (textureImage != null) {
      canvas.drawImage(
        textureImage!,
        ui.Offset.zero,
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
    }
    _debugFrameCount++;
  }

  /// Check if a position is walkable based on the mask.
  /// Black pixels (RGB < 50) are walkable, white pixels are blocked.
  /// Positions outside the map bounds are always blocked.
  bool isWalkable(Vector2 pos) {
    if (maskBytes == null || maskImage == null) {
      return true;
    }
    
    // First, check if the position is within map bounds
    // We need to check all corners of the player to ensure nothing is out of bounds
    final playerSize = 32.0;
    final halfSize = playerSize / 2;
    
    // Add a small safety margin to prevent getting right at the edge
    final safetyMargin = 2.0;
    
    // Calculate the bounding box of the player with safety margin
    final minX = pos.x - halfSize - safetyMargin;
    final maxX = pos.x + halfSize + safetyMargin;
    final minY = pos.y - halfSize - safetyMargin;
    final maxY = pos.y + halfSize + safetyMargin;
    
    // If ANY part of the player (including safety margin) is outside the map bounds, it's not walkable
    if (minX < 0 || maxX >= maskImage!.width || minY < 0 || maxY >= maskImage!.height) {
      return false; // Out of bounds - blocked
    }
    
    // Check multiple points around the player position to ensure the entire character doesn't overlap blocked areas
    final checkPoints = [
      pos, // Center
      Vector2(pos.x - halfSize, pos.y - halfSize), // Top-left
      Vector2(pos.x + halfSize, pos.y - halfSize), // Top-right
      Vector2(pos.x - halfSize, pos.y + halfSize), // Bottom-left
      Vector2(pos.x + halfSize, pos.y + halfSize), // Bottom-right
      Vector2(pos.x, pos.y - halfSize), // Top-center
      Vector2(pos.x, pos.y + halfSize), // Bottom-center
      Vector2(pos.x - halfSize, pos.y), // Left-center
      Vector2(pos.x + halfSize, pos.y), // Right-center
    ];
    
    for (final checkPos in checkPoints) {
      // Convert world coordinates to image coordinates (no clamping needed since we already checked bounds)
      final px = checkPos.x.toInt();
      final py = checkPos.y.toInt();
      
      // Double-check bounds (shouldn't be needed, but safety check)
      if (px < 0 || px >= maskImage!.width || py < 0 || py >= maskImage!.height) {
        return false; // Out of bounds
      }
      
      final offset = (py * maskImage!.width + px) * 4;
      
      if (offset >= maskBytes!.lengthInBytes) {
        return false;
      }
      
      final r = maskBytes!.getUint8(offset);
      final g = maskBytes!.getUint8(offset+1);
      final b = maskBytes!.getUint8(offset+2);
      
      // Extremely strict white detection - any pixel that's not pure black is blocked
      final isWhite = r > 50 || g > 50 || b > 50;
      
      // If any point is blocked, the entire position is not walkable
      if (isWhite) {
        // Only print debug info occasionally to reduce performance impact
        if (px % 50 == 0 && py % 50 == 0) {
          print('Blocked at ($px, $py): RGB($r, $g, $b) - WHITE');
        }
        return false;
      }
    }
    
    return true;
  }
}
