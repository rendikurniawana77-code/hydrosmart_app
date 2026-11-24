import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/hydro_control.dart';
import '../models/hydro_latest.dart';
import '../providers/hydrosmart_provider.dart';
import '../repositories/hydro_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _responseTimeout = Duration(seconds: 12);
  static const _stuckCommandTimeout = Duration(seconds: 15);
  static const _calibrationMessageLifetime = Duration(seconds: 10);

  late final HydroRepository _repository;
  StreamSubscription<HydroLatest?>? _latestSubscription;
  StreamSubscription<HydroControl?>? _controlSubscription;
  Timer? _clockTimer;
  HydroLatest? _latest;
  HydroControl? _control;
  Completer<void>? _resetWaiter;
  Completer<void>? _calibrationWaiter;
  bool _sedangMengirimReset = false;
  bool _sedangMengirimKalibrasi = false;
  bool _resetDibalasGalatMasihAktif = false;
  int? _resetPreviousTime;
  int? _calibrationPreviousTime;
  DateTime? _resetProcessingSince;
  DateTime? _calibrationProcessingSince;
  DateTime? _calibrationSentAt;

  bool get _isOnline {
    final waktu = _latest?.waktu;
    if (waktu == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now - waktu < 30;
  }

  bool get _isBusy => _sedangMengirimReset || _sedangMengirimKalibrasi;

  @override
  void initState() {
    super.initState();
    _repository = Provider.of<HydroSmartProvider>(
      context,
      listen: false,
    ).hydroRepository;
    _latestSubscription = _repository.latestStream.listen((latest) {
      if (!mounted) return;
      setState(() {
        _latest = latest;
        if (latest?.galat == false) _resetDibalasGalatMasihAktif = false;
      });
      _checkWaiters();
    }, onError: (Object error) => debugPrint('Stream terbaru gagal: $error'));
    _controlSubscription = _repository.controlStream.listen((control) {
      if (!mounted) return;
      setState(() {
        _control = control;
        _observeControl(control);
      });
      _checkWaiters();
    }, onError: (Object error) => debugPrint('Stream kontrol gagal: $error'));
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _checkWaiters() {
    final resetAcknowledged = !(_control?.resetDiproses ?? false);
    if (_sedangMengirimReset &&
        resetAcknowledged &&
        _latest?.waktu != _resetPreviousTime) {
      if (!(_resetWaiter?.isCompleted ?? true)) _resetWaiter!.complete();
    }

    final calibrationWaiter = _calibrationWaiter;
    if (_sedangMengirimKalibrasi &&
        (_control?.kalibrasiIdle ?? true) &&
        _latest?.waktu != _calibrationPreviousTime &&
        calibrationWaiter != null &&
        !calibrationWaiter.isCompleted) {
      calibrationWaiter.complete();
    }
  }

  void _observeControl(HydroControl? control) {
    final now = DateTime.now();
    if (control?.resetDiproses == true) {
      _resetProcessingSince ??= now;
    } else {
      _resetProcessingSince = null;
    }
    if (control?.kalibrasiIdle == false) {
      _calibrationProcessingSince ??= now;
    } else {
      _calibrationProcessingSince = null;
    }
  }

  Future<bool?> _checkPreviousCommand({
    required bool isReset,
    bool staleCommandApproved = false,
  }) async {
    final current = await _repository.bacaKontrol();
    _observeControl(current);
    final processing = isReset
        ? current?.resetDiproses == true
        : current?.kalibrasiIdle == false;
    if (!processing) return false;

    final processingSince = isReset
        ? _resetProcessingSince
        : _calibrationProcessingSince;
    final age = processingSince == null
        ? Duration.zero
        : DateTime.now().difference(processingSince);
    if (age < _stuckCommandTimeout) {
      _showMessage('Perintah sebelumnya masih diproses perangkat');
      return null;
    }
    if (staleCommandApproved) return true;

    final retry = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Perintah macet'),
        content: const Text(
          'Perintah sebelumnya tidak diambil perangkat. Kirim ulang?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kirim Ulang'),
          ),
        ],
      ),
    );
    if (retry != true || !mounted) return null;

    final verified = await _repository.bacaKontrol();
    _observeControl(verified);
    final stillProcessing = isReset
        ? verified?.resetDiproses == true
        : verified?.kalibrasiIdle == false;
    if (!stillProcessing) return false;

    final verifiedSince = isReset
        ? _resetProcessingSince
        : _calibrationProcessingSince;
    if (verifiedSince != null &&
        DateTime.now().difference(verifiedSince) >= _stuckCommandTimeout) {
      return true;
    }
    _showMessage('Perintah sebelumnya masih diproses perangkat');
    return null;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _resetError() async {
    if (_isBusy ||
        !_isOnline ||
        _latest?.galat != true ||
        _resetDibalasGalatMasihAktif) {
      return;
    }
    setState(() => _sedangMengirimReset = true);
    var sentAt = DateTime.now();
    var writeSucceeded = false;

    try {
      var staleCommandApproved = await _checkPreviousCommand(isReset: true);
      if (staleCommandApproved == null) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reset galat?'),
          content: const Text(
            'Cek penyebab galat (tandon, selang, pompa, sensor) sebelum reset, '
            'kalau tidak galat bisa terkunci lagi.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reset Galat'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      staleCommandApproved = await _checkPreviousCommand(
        isReset: true,
        staleCommandApproved: staleCommandApproved,
      );
      if (staleCommandApproved == null) return;

      final waiter = Completer<void>();
      _resetWaiter = waiter;
      _resetPreviousTime = _latest?.waktu;
      await _repository.kirimReset();
      sentAt = DateTime.now();
      writeSucceeded = true;
      _resetProcessingSince = null;
      _checkWaiters();

      try {
        await waiter.future.timeout(_responseTimeout);
        if (_latest?.galat == false) {
          _showMessage('Galat direset');
        } else {
          _resetDibalasGalatMasihAktif = true;
          final reason = _latest?.alasan?.trim();
          _showMessage(
            reason == null || reason.isEmpty ? 'Galat masih aktif' : reason,
          );
        }
      } on TimeoutException {
        _showMessage('Perangkat belum merespons');
      }
    } catch (error) {
      _showMessage('Gagal mengirim reset galat: $error');
    } finally {
      if (writeSucceeded) {
        final remaining =
            const Duration(seconds: 3) - DateTime.now().difference(sentAt);
        if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      }
      if (mounted) {
        setState(() {
          _sedangMengirimReset = false;
          _resetWaiter = null;
          _resetPreviousTime = null;
        });
      }
    }
  }

  Future<void> _calibrate(String command) async {
    if (_isBusy || !_isOnline || _latest?.pompa == true) {
      return;
    }
    setState(() => _sedangMengirimKalibrasi = true);
    var sentAt = DateTime.now();
    var writeSucceeded = false;

    try {
      var staleCommandApproved = await _checkPreviousCommand(isReset: false);
      if (staleCommandApproved == null) return;

      if (command == 'reset') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Hapus kalibrasi?'),
            content: const Text(
              'Kalibrasi sensor akan dihapus. Anda perlu melakukan kalibrasi '
              'kering dan basah kembali.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Hapus Kalibrasi'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }

      staleCommandApproved = await _checkPreviousCommand(
        isReset: false,
        staleCommandApproved: staleCommandApproved,
      );
      if (staleCommandApproved == null) return;

      final previousTime = _latest?.waktu;
      final waiter = Completer<void>();
      _calibrationPreviousTime = previousTime;
      _calibrationWaiter = waiter;
      await _repository.kirimKalibrasi(command);
      sentAt = DateTime.now();
      writeSucceeded = true;
      _calibrationSentAt = sentAt;
      _calibrationProcessingSince = null;
      if (mounted) setState(() {});
      _checkWaiters();

      try {
        await waiter.future.timeout(_responseTimeout);
        final message =
            DateTime.now().difference(sentAt) <= _calibrationMessageLifetime
            ? _latest?.kalPesan?.trim()
            : null;
        _showMessage(
          message == null || message.isEmpty
              ? 'Perintah kalibrasi telah diproses'
              : message,
        );
      } on TimeoutException {
        _showMessage('Perangkat belum merespons');
      }
    } on TimeoutException {
      _showMessage('Perangkat belum merespons');
    } catch (error) {
      _showMessage('Gagal mengirim kalibrasi: $error');
    } finally {
      if (writeSucceeded) {
        final remaining =
            const Duration(seconds: 3) - DateTime.now().difference(sentAt);
        if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      }
      if (mounted) {
        setState(() {
          _sedangMengirimKalibrasi = false;
          _calibrationWaiter = null;
          _calibrationPreviousTime = null;
        });
      }
    }
  }

  Widget _checkStatus(String label, bool? isOk) {
    final icon = isOk == true ? Icons.check_circle : Icons.cancel;
    final color = isOk == true ? const Color(0xFF059669) : Colors.red.shade700;
    final value = isOk == null ? 'Belum diketahui' : (isOk ? 'OK' : 'Belum');
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  String _calibrationStatusMessage(HydroLatest? latest) {
    final sentAt = _calibrationSentAt;
    if (sentAt == null ||
        DateTime.now().difference(sentAt) > _calibrationMessageLifetime) {
      return 'Belum ada hasil kalibrasi baru';
    }
    final message = latest?.kalPesan?.trim();
    return message == null || message.isEmpty
        ? 'Menunggu hasil kalibrasi'
        : message;
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<HydroSmartProvider>(context);
    final latest = _latest;
    final online = _isOnline;
    final pumpRunning = latest?.pompa == true;
    final canReset =
        online &&
        latest?.galat == true &&
        !_resetDibalasGalatMasihAktif &&
        !_isBusy;
    final canCalibrate = online && !pumpRunning && !_isBusy;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Pengaturan',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ),
              Icon(
                online ? Icons.cloud_done : Icons.cloud_off,
                color: online ? const Color(0xFF059669) : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                online ? 'Online' : 'Offline',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: online ? const Color(0xFF059669) : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildThresholdCard(provider, online),
          const SizedBox(height: 16),
          _buildErrorCard(latest, canReset),
          const SizedBox(height: 16),
          _buildCalibrationCard(latest, canCalibrate, pumpRunning),
        ],
      ),
    );
  }

  Widget _buildThresholdCard(HydroSmartProvider provider, bool online) {
    final canEdit = provider.currentRole == UserRole.admin && online;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ambang Batas Air',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text('Batas Bawah Pompa Nyala: ${provider.minWaterLevel.toInt()}%'),
            Slider(
              value: provider.minWaterLevel,
              min: 10,
              max: 50,
              activeColor: const Color(0xFF0284C7),
              onChanged: canEdit ? provider.setLowerWaterThreshold : null,
            ),
            const Divider(),
            Text('Batas Atas Pompa Mati: ${provider.maxWaterLevel.toInt()}%'),
            Slider(
              value: provider.maxWaterLevel,
              min: 50,
              max: 95,
              activeColor: const Color(0xFF059669),
              onChanged: canEdit ? provider.setUpperWaterThreshold : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(HydroLatest? latest, bool canReset) {
    final hasError = latest?.galat == true;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Status Sistem',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (hasError)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        latest?.alasan?.isNotEmpty == true
                            ? latest!.alasan!
                            : 'Galat terdeteksi',
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                    ),
                  ],
                ),
              )
            else if (latest?.galat == false)
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF059669)),
                  SizedBox(width: 8),
                  Text('Normal'),
                ],
              )
            else
              const Text('Status galat belum tersedia'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canReset ? _resetError : null,
                icon: _sedangMengirimReset
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restart_alt),
                label: const Text('Reset Galat'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalibrationCard(
    HydroLatest? latest,
    bool canCalibrate,
    bool pumpRunning,
  ) {
    final complete = latest?.kalLengkap == true;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kalibrasi Ketinggian Air',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Text('Status kalibrasi')),
                Text(
                  complete ? 'LENGKAP' : 'BELUM LENGKAP',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: complete
                        ? const Color(0xFF059669)
                        : Colors.orange.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _checkStatus('Kering', latest?.kalKeringOk),
            const SizedBox(height: 8),
            _checkStatus('Basah', latest?.kalBasahOk),
            if (latest?.kalPesan?.trim().isNotEmpty == true ||
                _calibrationSentAt != null) ...[
              const SizedBox(height: 12),
              Text(_calibrationStatusMessage(latest)),
            ],
            const SizedBox(height: 12),
            const Text(
              'Kering: sensor di udara atau bak kosong. Basah: sensor terendam '
              'sampai tinggi maksimum. Jangan gerakkan sensor sekitar 1 detik.',
            ),
            if (_sedangMengirimKalibrasi) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Memproses kalibrasi...'),
            ],
            if (pumpRunning) ...[
              const SizedBox(height: 8),
              Text(
                'Matikan pompa sebelum melakukan kalibrasi.',
                style: TextStyle(color: Colors.orange.shade900),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: canCalibrate ? () => _calibrate('kering') : null,
                  child: const Text('Kalibrasi KERING'),
                ),
                FilledButton(
                  onPressed: canCalibrate ? () => _calibrate('basah') : null,
                  child: const Text('Kalibrasi BASAH'),
                ),
                OutlinedButton(
                  onPressed: canCalibrate ? () => _calibrate('reset') : null,
                  child: const Text('Hapus Kalibrasi'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _latestSubscription?.cancel();
    _controlSubscription?.cancel();
    super.dispose();
  }
}
