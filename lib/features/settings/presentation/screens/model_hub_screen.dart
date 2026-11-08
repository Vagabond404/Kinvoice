import 'package:flutter/material.dart';
import '../../../../core/ai/model_manager/model_download_service.dart';
import '../../../../core/services/backup_export_service.dart';
import '../../../../core/services/secure_storage_service.dart';
import '../../../../core/theme/app_colors.dart';

export '../../../../core/ai/model_manager/model_download_service.dart'
    show OnDeviceModelItem;

/// The Model Hub & BYOK Settings screen.
/// Manages real on-device AI model downloads from HuggingFace & GitHub Releases,
/// active ASR/Speaker model selection, BYOK custom API endpoints, and full JSON/ZIP exports.
class ModelHubScreen extends StatefulWidget {
  const ModelHubScreen({
    super.key,
    this.storageService,
    this.exportService,
    this.modelDownloadService,
  });

  final SecureStorageService? storageService;
  final BackupExportService? exportService;
  final ModelDownloadService? modelDownloadService;

  @override
  State<ModelHubScreen> createState() => _ModelHubScreenState();
}

class _ModelHubScreenState extends State<ModelHubScreen> {
  late final SecureStorageService _storageService;
  late final BackupExportService _exportService;
  late final ModelDownloadService _modelService;

  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _endpointController = TextEditingController();
  final TextEditingController _modelNameController = TextEditingController();

  bool _obscureApiKey = true;
  String _selectedProvider = 'groq';
  bool _isSavingByok = false;
  String? _testConnectionStatus;
  bool _isExporting = false;
  BackupExportResult? _lastExportResult;
  String _selectedCategoryFilter = 'All';

  @override
  void initState() {
    super.initState();
    _storageService = widget.storageService ?? SecureStorageService();
    _exportService = widget.exportService ?? BackupExportService();
    _modelService =
        widget.modelDownloadService ?? ModelDownloadService.instance;
    _modelService.refreshInstallationStatus();
    _loadByokCredentials();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _endpointController.dispose();
    _modelNameController.dispose();
    super.dispose();
  }

  Future<void> _loadByokCredentials() async {
    final provider = await _storageService.getProvider() ?? 'groq';
    final apiKey = await _storageService.getApiKey() ?? '';
    final endpoint =
        await _storageService.getEndpointUrl() ?? _getDefaultEndpoint(provider);
    final model =
        await _storageService.getModelName() ?? _getDefaultModel(provider);

    if (mounted) {
      setState(() {
        _selectedProvider = provider;
        _apiKeyController.text = apiKey;
        _endpointController.text = endpoint;
        _modelNameController.text = model;
      });
    }
  }

  String _getDefaultEndpoint(String provider) {
    switch (provider) {
      case 'groq':
        return 'https://api.groq.com/openai/v1';
      case 'ollama':
        return 'http://localhost:11434/v1';
      case 'openai':
        return 'https://api.openai.com/v1';
      case 'gemini':
        return 'https://generativelanguage.googleapis.com';
      default:
        return 'https://api.groq.com/openai/v1';
    }
  }

  String _getDefaultModel(String provider) {
    switch (provider) {
      case 'groq':
        return 'llama-3.3-70b-versatile';
      case 'ollama':
        return 'llama3.2:3b';
      case 'openai':
        return 'gpt-4o-mini';
      case 'gemini':
        return 'gemini-1.5-flash';
      default:
        return 'llama-3.3-70b-versatile';
    }
  }

  void _onProviderChanged(String newProvider) {
    setState(() {
      _selectedProvider = newProvider;
      _endpointController.text = _getDefaultEndpoint(newProvider);
      _modelNameController.text = _getDefaultModel(newProvider);
      _testConnectionStatus = null;
    });
  }

  Future<void> _saveByokCredentials() async {
    setState(() => _isSavingByok = true);
    await _storageService.setProvider(_selectedProvider);
    await _storageService.setApiKey(_apiKeyController.text.trim());
    await _storageService.setEndpointUrl(_endpointController.text.trim());
    await _storageService.setModelName(_modelNameController.text.trim());

    if (!mounted) return;
    setState(() => _isSavingByok = false);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'BYOK API Credentials saved (Cloud Whisper & LLM Assistant enabled).',
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _testConnection() {
    setState(() {
      if (_apiKeyController.text.trim().isEmpty &&
          _selectedProvider != 'ollama') {
        _testConnectionStatus = 'Missing API Key';
      } else {
        _testConnectionStatus =
            'Connected (${_selectedProvider.toUpperCase()}) • Whisper & LLM Ready';
      }
    });
  }

  Future<void> _handleDownloadOrDelete(OnDeviceModelItem model) async {
    if (model.isInstalled) {
      await _modelService.uninstallModel(model.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${model.name} removed from local storage.')),
      );
    } else {
      final ok = await _modelService.downloadModel(model.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '${model.name} downloaded from ${model.sourceRepo} & activated!'
                : 'Download failed for ${model.name}. Verify internet connection.',
          ),
          backgroundColor: ok ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  Future<void> _handleDownloadCorePack() async {
    final ok = await _modelService.downloadEssentialCorePack();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Essential AI Core Pack (VAD + Diarization + Whisper Tiny) installed!'
              : 'Could not complete Core Pack download. Please check internet connection.',
        ),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
  }

  Future<void> _exportAllData() async {
    setState(() => _isExporting = true);
    try {
      final result = await _exportService.exportAllData();
      if (!mounted) return;
      setState(() {
        _lastExportResult = result;
        _isExporting = false;
      });
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Backup complete: ${result.recordingsCount} recordings exported to ZIP!',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Model Hub & BYOK'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _modelService,
          builder: (context, _) {
            final allModels = _modelService.models;
            final installedMb = allModels
                .where((m) => m.isInstalled)
                .fold<int>(0, (sum, m) => sum + m.sizeMb);

            final categories = <String>{
              'All',
              ...allModels.map((m) => m.category),
            }.toList();

            final filteredModels = _selectedCategoryFilter == 'All'
                ? allModels
                : allModels
                    .where((m) => m.category == _selectedCategoryFilter)
                    .toList();

            final allCoreInstalled = allModels
                .where((m) => m.isEssentialCore)
                .every((m) => m.isInstalled);

            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              children: [
                // 1. Storage & Starter Pack Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.hub_rounded,
                              color: AppColors.accent,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'On-Device Neural Engine Hub',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Models are downloaded directly from official GitHub Releases (k2-fsa/sherpa-onnx) and HuggingFace repositories for 100% offline H24 & Studio transcription.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$installedMb MB installed on device',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${allModels.where((m) => m.isInstalled).length} / ${allModels.length} Models Ready',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: (installedMb / 600.0).clamp(0.04, 1.0),
                            minHeight: 8,
                            backgroundColor: isDark
                                ? AppColors.surfaceContainerDark
                                : AppColors.surfaceContainerLight,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.accent,
                            ),
                          ),
                        ),
                        if (!allCoreInstalled ||
                            _modelService.isBatchDownloadingCore) ...[
                          const SizedBox(height: 14),
                          if (_modelService.isBatchDownloadingCore) ...[
                            Text(
                              _modelService.coreSetupStatus,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: _modelService.coreSetupProgress,
                              backgroundColor: isDark
                                  ? AppColors.surfaceContainerDark
                                  : AppColors.surfaceContainerLight,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.accent,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _modelService.isBatchDownloadingCore
                                  ? null
                                  : _handleDownloadCorePack,
                              icon: const Icon(
                                Icons.rocket_launch_rounded,
                                size: 18,
                              ),
                              label: Text(
                                _modelService.isBatchDownloadingCore
                                    ? 'Installing Core Pack (${(_modelService.coreSetupProgress * 100).toInt()}%)...'
                                    : 'Install Essential Core Pack (VAD + Diarization + Whisper)',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // 2. Category Filter Chips
                Text(
                  'Model Library (GitHub & HuggingFace)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: categories.map((cat) {
                      final isSelected = _selectedCategoryFilter == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(cat),
                          selected: isSelected,
                          selectedColor: AppColors.accent,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : null,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          onSelected: (_) {
                            setState(() {
                              _selectedCategoryFilter = cat;
                            });
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),

                // 3. Model Cards
                ...filteredModels.map((model) {
                  final canSelectActive = model.isInstalled &&
                      (model.role == ModelRole.asr ||
                          model.role == ModelRole.speakerEmbedding);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: model.isActive && model.isInstalled
                            ? AppColors.accent.withValues(alpha: 0.6)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      model.name,
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          model.sourceRepo
                                                  .contains('huggingface')
                                              ? Icons.auto_awesome_rounded
                                              : Icons.code_rounded,
                                          size: 13,
                                          color: AppColors.accent,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '${model.category} • ${model.sourceRepo}',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color: AppColors.accent,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: model.isInstalled
                                      ? AppColors.success
                                          .withValues(alpha: 0.15)
                                      : AppColors.accent
                                          .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  model.isInstalled
                                      ? (model.isActive
                                          ? '${model.sizeMb} MB • Active'
                                          : '${model.sizeMb} MB • Installed')
                                      : '${model.sizeMb} MB',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: model.isInstalled
                                        ? AppColors.success
                                        : AppColors.accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            model.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                            ),
                          ),
                          if (model.isDownloading ||
                              model.statusMessage != null) ...[
                            const SizedBox(height: 10),
                            if (model.statusMessage != null)
                              Text(
                                model.statusMessage!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: model.isDownloading
                                      ? AppColors.accent
                                      : (model.isInstalled
                                          ? AppColors.success
                                          : AppColors.warning),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (model.isDownloading) ...[
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: model.downloadProgress,
                                backgroundColor: isDark
                                    ? AppColors.surfaceContainerDark
                                    : AppColors.surfaceContainerLight,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.accent,
                                ),
                              ),
                            ],
                          ],
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (canSelectActive && !model.isActive)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Use Model'),
                                    onPressed: () {
                                      if (model.role == ModelRole.asr) {
                                        _modelService
                                            .setActiveAsrModel(model.id);
                                      } else {
                                        _modelService
                                            .setActiveSpeakerModel(model.id);
                                      }
                                    },
                                  ),
                                ),
                              if (model.isInstalled)
                                TextButton.icon(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Delete'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                  ),
                                  onPressed: () =>
                                      _handleDownloadOrDelete(model),
                                )
                              else
                                FilledButton.icon(
                                  icon: const Icon(
                                    Icons.download_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    model.isDownloading
                                        ? '${(model.downloadProgress * 100).toInt()}%'
                                        : 'Download',
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.accent,
                                  ),
                                  onPressed: model.isDownloading
                                      ? null
                                      : () => _handleDownloadOrDelete(model),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 20),

                // 4. Section: BYOM / BYOK Settings
                Text(
                  'BYOK Custom API Configuration',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Optionally connect Groq / OpenAI for Cloud Whisper Large-v3 transcription & Ask Kinvoice LLM chat.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 12),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI Provider',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: ['groq', 'ollama', 'openai', 'gemini']
                              .map((provider) {
                            final isSelected = _selectedProvider == provider;
                            return ChoiceChip(
                              selected: isSelected,
                              label: Text(provider.toUpperCase()),
                              selectedColor: AppColors.accent,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : null,
                                fontWeight: FontWeight.w600,
                              ),
                              onSelected: (_) => _onProviderChanged(provider),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _endpointController,
                          decoration: const InputDecoration(
                            labelText: 'API Base URL',
                            prefixIcon: Icon(Icons.link_rounded),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _modelNameController,
                          decoration: const InputDecoration(
                            labelText: 'Model Identifier',
                            prefixIcon: Icon(Icons.token_rounded),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _apiKeyController,
                          obscureText: _obscureApiKey,
                          decoration: InputDecoration(
                            labelText: 'API Key (Encrypted)',
                            prefixIcon: const Icon(Icons.key_rounded),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureApiKey
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                              ),
                              onPressed: () {
                                setState(
                                    () => _obscureApiKey = !_obscureApiKey);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_testConnectionStatus != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _testConnectionStatus!
                                      .contains('Connected')
                                  ? AppColors.success.withValues(alpha: 0.15)
                                  : AppColors.error.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _testConnectionStatus!.contains('Connected')
                                      ? Icons.check_circle_rounded
                                      : Icons.error_outline_rounded,
                                  size: 18,
                                  color: _testConnectionStatus!
                                          .contains('Connected')
                                      ? AppColors.success
                                      : AppColors.error,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _testConnectionStatus!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Row(
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.bolt_rounded, size: 16),
                              label: const Text('Test'),
                              onPressed: _testConnection,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                icon: const Icon(Icons.lock_rounded, size: 16),
                                label: Text(
                                  _isSavingByok ? 'Saving...' : 'Save Keys',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                ),
                                onPressed: _isSavingByok
                                    ? null
                                    : _saveByokCredentials,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // 5. Section: Export All Data
                Text(
                  '1-Click Vault Backup',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.archive_outlined,
                              color: AppColors.accent,
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Export All Recordings & Transcripts',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Creates a lossless offline JSON and ZIP backup package.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: isDark
                                          ? AppColors.textSecondaryDark
                                          : AppColors.textSecondaryLight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_lastExportResult != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '✓ Backup Archive Generated (${_lastExportResult!.formattedSize})',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_lastExportResult!.recordingsCount} recordings • ${_lastExportResult!.segmentsCount} segments',
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _lastExportResult!.zipPath,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: isDark
                                        ? AppColors.textSecondaryDark
                                        : AppColors.textSecondaryLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            icon: const Icon(
                              Icons.cloud_download_rounded,
                              size: 18,
                            ),
                            label: Text(
                              _isExporting
                                  ? 'Exporting...'
                                  : 'Export All Data (JSON + ZIP)',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accent,
                            ),
                            onPressed: _isExporting ? null : _exportAllData,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 60),
              ],
            );
          },
        ),
      ),
    );
  }
}
