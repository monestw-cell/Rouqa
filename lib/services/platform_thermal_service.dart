/// platform_thermal_service.dart
/// خدمة قراءة بيانات الحرارة والبطارية من منصة Android
///
/// تستخدم MethodChannel للتواصل مع الكود الأصلي (Kotlin)
/// للحصول على بيانات دقيقة عن:
/// - درجة حرارة البطارية
/// - مستوى البطارية وحالة الشحن
/// - وضع توفير الطاقة
/// - فئة أداء الجهاز (Android Performance Class)
/// - حالة الحرارة من PowerManager (API 29+)

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'thermal_monitor.dart';

// ============================================================================
/// بيانات الحرارة والبطارية من المنصة — Platform Thermal Data
class PlatformThermalData {
  /// مستوى البطارية (0-100)
  final int batteryLevel;

  /// هل البطارية مشحونة؟
  final bool isCharging;

  /// وضع توفير الطاقة
  final bool isPowerSave;

  /// درجة حرارة البطارية (درجة مئوية)
  final double? batteryTemperature;

  /// حالة حرارة الجهاز من PowerManager (API 29+)
  /// القيم: 0 = لا حرارة، 1 = خفيف، 2 = متوسط، 3 = شديد
  final int? thermalStatus;

  /// فئة أداء الجهاز (API 31+)
  /// القيم: 0 = غير معروف، 1 = منخفض، 2 = متوسط، 3 = عالي
  final int? performanceClass;

  /// الذاكرة المتاحة (MB)
  final int? availableMemoryMb;

  /// هل المنصة مدعومة؟
  final bool isSupported;

  const PlatformThermalData({
    this.batteryLevel = 100,
    this.isCharging = false,
    this.isPowerSave = false,
    this.batteryTemperature,
    this.thermalStatus,
    this.performanceClass,
    this.availableMemoryMb,
    this.isSupported = false,
  });

  /// تحويل من Map (استجابة MethodChannel)
  factory PlatformThermalData.fromMap(Map<dynamic, dynamic> map) {
    return PlatformThermalData(
      batteryLevel: map['batteryLevel'] as int? ?? 100,
      isCharging: map['isCharging'] as bool? ?? false,
      isPowerSave: map['isPowerSave'] as bool? ?? false,
      batteryTemperature: (map['batteryTemperature'] as num?)?.toDouble(),
      thermalStatus: map['thermalStatus'] as int?,
      performanceClass: map['performanceClass'] as int?,
      availableMemoryMb: map['availableMemoryMb'] as int?,
      isSupported: map['isSupported'] as bool? ?? false,
    );
  }

  /// تحويل إلى BatteryInfo
  BatteryInfo toBatteryInfo() {
    return BatteryInfo(
      level: batteryLevel,
      isCharging: isCharging,
      isPowerSave: isPowerSave,
      temperature: batteryTemperature,
    );
  }

  /// تحويل إلى DevicePerformanceClass
  DevicePerformanceClass toPerformanceClass() {
    switch (performanceClass) {
      case 1:
        return DevicePerformanceClass.low;
      case 2:
        return DevicePerformanceClass.medium;
      case 3:
        return DevicePerformanceClass.high;
      default:
        return DevicePerformanceClass.unknown;
    }
  }

  /// تحويل إلى ThermalState (من PowerManager thermalStatus)
  ThermalState toThermalState() {
    switch (thermalStatus) {
      case 0:
        return ThermalState.normal;
      case 1:
        return ThermalState.warm;
      case 2:
        return ThermalState.hot;
      case 3:
        return ThermalState.critical;
      default:
        // إذا لم يتوفر thermalStatus، نُقدّر من درجة حرارة البطارية
        if (batteryTemperature != null) {
          if (batteryTemperature! > 42) return ThermalState.critical;
          if (batteryTemperature! > 39) return ThermalState.hot;
          if (batteryTemperature! > 36) return ThermalState.warm;
        }
        return ThermalState.normal;
    }
  }
}

// ============================================================================
/// خدمة الحرارة عبر Platform Channel — Platform Thermal Service
///
/// تتواصل مع الكود الأصلي (Kotlin) للحصول على بيانات
/// حرارة وبطارية حقيقية من APIs نظام Android.
///
/// الاستخدام:
/// ```dart
/// final service = PlatformThermalService();
/// final data = await service.getThermalData();
///
/// // استخدام البيانات
/// monitor.updateBatteryInfo(data.toBatteryInfo());
/// monitor.updatePerformanceClass(data.toPerformanceClass());
/// ```
class PlatformThermalService {
  static const _tag = 'PlatformThermalService';

  /// اسم القناة — Must match MainActivity.kt
  static const _channel = MethodChannel('com.ruqa.chessanalyzer/thermal');

  /// هل المنصة مدعومة؟ (Android فقط)
  bool _isPlatformSupported = false;

  /// هل تم التحقق من المنصة؟
  bool _hasCheckedPlatform = false;

  PlatformThermalService() {
    _checkPlatform();
  }

  // ========================================================================
  // كشف المنصة
  // ========================================================================

  /// التحقق من أن المنصة مدعومة
  void _checkPlatform() {
    if (_hasCheckedPlatform) return;
    _hasCheckedPlatform = true;

    try {
      _isPlatformSupported = !kIsWeb && Platform.isAndroid;
    } catch (_) {
      _isPlatformSupported = false;
    }

    debugPrint('$_tag: المنصة المدعومة: $_isPlatformSupported');
  }

  /// هل المنصة مدعومة؟
  bool get isPlatformSupported => _isPlatformSupported;

  // ========================================================================
  // قراءة البيانات
  // ========================================================================

  /// قراءة بيانات الحرارة والبطارية من المنصة
  ///
  /// تُرجع [PlatformThermalData] مع البيانات الحقيقية إن توفرت،
  /// أو بيانات افتراضية إذا لم تكن المنصة مدعومة.
  Future<PlatformThermalData> getThermalData() async {
    if (!_isPlatformSupported) {
      return const PlatformThermalData(isSupported: false);
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getThermalData',
      );

      if (result != null) {
        return PlatformThermalData.fromMap(result);
      }
    } on PlatformException catch (e) {
      debugPrint('$_tag: خطأ في قراءة بيانات الحرارة: ${e.message}');
    } on MissingPluginException catch (e) {
      debugPrint('$_tag: الإضافة غير مسجلة: $e');
    } catch (e) {
      debugPrint('$_tag: خطأ غير متوقع: $e');
    }

    return const PlatformThermalData(isSupported: false);
  }

  /// طلب إعفاء من تحسين البطارية — Request battery optimization exemption
  ///
  /// يعرض على المستخدم مربع حوار لإضافة التطبيق إلى القائمة البيضاء
  /// لمنع Android من تقييد التطبيق في الخلفية.
  Future<bool> requestBatteryOptimizationExemption() async {
    if (!_isPlatformSupported) return false;

    try {
      final result = await _channel.invokeMethod<bool>(
        'requestBatteryOptimizationExemption',
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('$_tag: خطأ في طلب إعفاء البطارية: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('$_tag: خطأ غير متوقع: $e');
      return false;
    }
  }

  /// التحقق مما إذا كان التطبيق معفى من تحسين البطارية
  Future<bool> isBatteryOptimizationExempted() async {
    if (!_isPlatformSupported) return false;

    try {
      final result = await _channel.invokeMethod<bool>(
        'isBatteryOptimizationExempted',
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('$_tag: خطأ في التحقق من إعفاء البطارية: ${e.message}');
      return false;
    } catch (e) {
      return false;
    }
  }
}
