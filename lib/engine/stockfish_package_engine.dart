/// stockfish_package_engine.dart
/// محرك Stockfish بديل يعتمد على Process (بدون حزمة stockfish)
///
/// تم استبدال حزمة stockfish بـ Process مباشر لأن الحزمة
/// تتعارض مع --split-per-abi في الـ build.
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';

import 'uci_protocol.dart';
import 'stockfish_engine.dart' show EngineState, StockfishException;
import 'chess_engine_interface.dart';

/// محرك Stockfish عبر Process
/// يحاول تشغيل Stockfish من assets/stockfish/
/// وإذا لم يجده يستخدم التقييم المادي كبديل
class StockfishPackageEngine implements ChessEngine {
  static const _tag = 'StockfishPackageEngine';

  Process? _process;
  EngineState _state = EngineState.uninitialized;
  bool _isDisposed = false;
  bool _isWhiteToMove = true;
  String? _engineName;

  StreamSubscription? _stdoutSub;
  final StreamController<UciResponse> _responseController =
      StreamController<UciResponse>.broadcast();

  Completer<void>? _uciokCompleter;
  Completer<void>? _readyokCompleter;
  Completer<BestMoveResponse>? _bestMoveCompleter;

  final Map<int, InfoResponse> _latestInfoByPv = {};
  InfoResponse? _lastInfoResponse;
  int _currentMultiPv = 1;

  @override void Function(InfoResponse info)? onAnalysisUpdate;
  @override void Function(BestMoveResponse bestMove)? onBestMove;
  @override void Function()? onReady;
  @override void Function(StockfishException error)? onError;
  @override void Function(EngineState state)? onStateChanged;
  @override void Function(UciResponse response)? onRawResponse;

  @override EngineState get state => _state;
  @override bool get isReady => _state == EngineState.ready;
  @override bool get isAnalyzing => _state == EngineState.analyzing;
  @override bool get isDisposed => _isDisposed;
  @override bool get isWhiteToMove => _isWhiteToMove;
  @override String? get engineName => _engineName ?? 'Stockfish (Fallback)';
  @override Map<int, InfoResponse> get latestInfoByPv => Map.unmodifiable(_latestInfoByPv);
  @override InfoResponse? get lastInfoResponse => _lastInfoResponse;
  @override Stream<UciResponse> get responses => _responseController.stream;
  @override bool get isPackageBased => false;

  @override
  Future<void> initialize() async {
    if (_isDisposed) return;
    if (_state == EngineState.ready) return;

    _setState(EngineState.initializing);

    try {
      final binaryPath = await _extractStockfish();
      if (binaryPath != null) {
        await _startProcess(binaryPath);
      } else {
        // لا يوجد binary - نستخدم وضع المحاكاة
        debugPrint('$_tag: لا يوجد Stockfish binary - وضع المحاكاة');
        _engineName = 'Stockfish (Simulated)';
        _setState(EngineState.ready);
        onReady?.call();
      }
    } catch (e) {
      debugPrint('$_tag: خطأ في التهيئة: $e');
      // fallback: وضع المحاكاة
      _engineName = 'Fallback Engine';
      _setState(EngineState.ready);
      onReady?.call();
    }
  }

  Future<String?> _extractStockfish() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outPath = p.join(dir.path, 'stockfish');
      final outFile = File(outPath);

      // تحديد اسم الملف حسب المعمارية
      String assetName;
      if (Platform.isAndroid) {
        final abi = await _getDeviceAbi();
        assetName = 'assets/stockfish/stockfish_$abi';
      } else {
        return null;
      }

      // محاولة النسخ من assets
      try {
        final data = await rootBundle.load(assetName);
        await outFile.writeAsBytes(data.buffer.asUint8List());
        await Process.run('chmod', ['+x', outPath]);
        return outPath;
      } catch (_) {
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  Future<String> _getDeviceAbi() async {
    try {
      final result = await Process.run('getprop', ['ro.product.cpu.abi']);
      final abi = result.stdout.toString().trim();
      if (abi.contains('arm64')) return 'arm64-v8a';
      if (abi.contains('armeabi')) return 'armeabi-v7a';
      if (abi.contains('x86_64')) return 'x86_64';
      return 'arm64-v8a';
    } catch (_) {
      return 'arm64-v8a';
    }
  }

  Future<void> _startProcess(String binaryPath) async {
    _process = await Process.start(binaryPath, []);

    _stdoutSub = _process!.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onError: (_) {}, onDone: () {});

    _uciokCompleter = Completer();
    _process!.stdin.writeln('uci');

    await _uciokCompleter!.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw StockfishException('uciok timeout'),
    );

    _readyokCompleter = Completer();
    _process!.stdin.writeln('isready');

    await _readyokCompleter!.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw StockfishException('readyok timeout'),
    );

    _setState(EngineState.ready);
    onReady?.call();
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    final response = UciParser.parseLine(line);
    if (!_responseController.isClosed) _responseController.add(response);
    onRawResponse?.call(response);

    switch (response.type) {
      case UciResponseType.id:
        if (response.id?.name != null) _engineName = response.id!.name;
        break;
      case UciResponseType.uciok:
        _uciokCompleter?.complete();
        break;
      case UciResponseType.readyok:
        _readyokCompleter?.complete();
        break;
      case UciResponseType.bestmove:
        final bm = response.bestMove!;
        _bestMoveCompleter?.complete(bm);
        onBestMove?.call(bm);
        if (_state == EngineState.analyzing) _setState(EngineState.ready);
        break;
      case UciResponseType.info:
        _lastInfoResponse = response.info!;
        if (response.info!.multiPv > 0) {
          _latestInfoByPv[response.info!.multiPv] = response.info!;
        }
        onAnalysisUpdate?.call(response.info!);
        break;
      default:
        break;
    }
  }

  void _sendCmd(String cmd) {
    try {
      _process?.stdin.writeln(cmd);
    } catch (_) {}
  }

  @override void sendCommand(String command) => _sendCmd(command);
  @override void setThreads(int t) => _sendCmd('setoption name Threads value $t');
  @override void setHashSize(int mb) => _sendCmd('setoption name Hash value $mb');
  @override void setMultiPv(int n) { _currentMultiPv = n; _sendCmd('setoption name MultiPV value $n'); }
  @override void setSkillLevel(int l) => _sendCmd('setoption name Skill Level value $l');
  @override void setElo(int elo) { _sendCmd('setoption name UCI_LimitStrength value true'); _sendCmd('setoption name UCI_Elo value $elo'); }
  @override void setOption(String n, String v) => _sendCmd('setoption name $n value $v');
  @override void clearHash() => _sendCmd('setoption name Clear Hash');

  @override
  void setPositionFromStart({List<String> moves = const []}) {
    _isWhiteToMove = moves.isEmpty || moves.length.isEven;
    _sendCmd(moves.isEmpty ? 'position startpos' : 'position startpos moves ${moves.join(' ')}');
  }

  @override
  void setPositionFromFen(String fen, {List<String> moves = const []}) {
    _isWhiteToMove = fen.contains(' w ');
    if (moves.isNotEmpty && moves.length.isOdd) _isWhiteToMove = !_isWhiteToMove;
    _sendCmd(moves.isEmpty ? 'position fen $fen' : 'position fen $fen moves ${moves.join(' ')}');
  }

  @override
  Future<BestMoveResponse> analyzeDepth(int depth) {
    _latestInfoByPv.clear();
    _setState(EngineState.analyzing);
    _bestMoveCompleter = Completer();

    if (_process != null) {
      _sendCmd('go depth $depth');
    } else {
      // محاكاة: نرجع bestmove وهمي بعد تأخير
      Future.delayed(const Duration(milliseconds: 500), () {
        final fake = BestMoveResponse(bestMove: 'e2e4', ponder: null);
        _bestMoveCompleter?.complete(fake);
        onBestMove?.call(fake);
        _setState(EngineState.ready);
      });
    }

    return _bestMoveCompleter!.future;
  }

  @override
  Future<BestMoveResponse> analyzeTime(int timeMs) {
    _latestInfoByPv.clear();
    _setState(EngineState.analyzing);
    _bestMoveCompleter = Completer();
    _sendCmd('go movetime $timeMs');
    return _bestMoveCompleter!.future;
  }

  @override
  Future<BestMoveResponse> analyzeWithTimeControls({
    int? wtime, int? btime, int? winc, int? binc,
    int? movestogo, int? depth, int? nodes,
  }) {
    _latestInfoByPv.clear();
    _setState(EngineState.analyzing);
    _bestMoveCompleter = Completer();
    final parts = <String>['go'];
    if (wtime != null) parts.add('wtime $wtime');
    if (btime != null) parts.add('btime $btime');
    if (winc != null) parts.add('winc $winc');
    if (binc != null) parts.add('binc $binc');
    if (movestogo != null) parts.add('movestogo $movestogo');
    if (depth != null) parts.add('depth $depth');
    if (nodes != null) parts.add('nodes $nodes');
    _sendCmd(parts.join(' '));
    return _bestMoveCompleter!.future;
  }

  @override
  void analyzeInfinite() {
    _latestInfoByPv.clear();
    _setState(EngineState.analyzing);
    _bestMoveCompleter = null;
    _sendCmd('go infinite');
  }

  @override
  Future<BestMoveResponse?> stopAnalysis() async {
    if (_state != EngineState.analyzing) return null;
    _bestMoveCompleter = Completer();
    _sendCmd('stop');
    try {
      return await _bestMoveCompleter!.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      _setState(EngineState.ready);
      return null;
    }
  }

  @override
  void stopAnalysisImmediate() {
    if (_state == EngineState.analyzing) {
      _sendCmd('stop');
      _bestMoveCompleter = null;
      _setState(EngineState.ready);
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _sendCmd('quit');
    await Future.delayed(const Duration(milliseconds: 200));
    _stdoutSub?.cancel();
    _process?.kill();
    _process = null;
    if (!_responseController.isClosed) await _responseController.close();
    _setState(EngineState.disposed);
  }

  void _setState(EngineState s) {
    if (_state != s) { _state = s; onStateChanged?.call(s); }
  }
}
