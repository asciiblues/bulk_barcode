import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' hide Border;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_barcodes/barcodes.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' hide Column, Row, Border;
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bulk Barcode Generator',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: Builder(builder: (_) => const MyHomePage()),
    );
  }
}

Future<void> openLink(String url) async {
  final Uri uri = Uri.parse(url);

  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw 'Could not launch $url';
  }
}

int barcodes = 0;
String barcodesText = '';

ImageIcon _getIconExcel() {
  if (kIsWeb || kIsWasm) {
    return const ImageIcon(
      NetworkImage('assets/description_24dp.png'), //Network image for web
    );
  } else {
    return const ImageIcon(
      AssetImage(
        'assets/description_24dp.png',
      ), // Local asset for mobile, desktop etc.
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final dataController = TextEditingController();
  final separatorController = TextEditingController(text: '\\n');
  bool isExported = false;
  bool isCustomSprt = false;

  final List<GlobalKey> _barcodeKeys = [];
  List<String> _dataList = [];
  List<String> _base64Images = [];
  List<Map<String, String>> _barcodeData = []; // Store data with base64
  bool _isGenerating = false;
  bool _isGeneratingPDF = false;
  bool _showValue = true;
  bool isExportedPdf = false;
  int _generatedBarcodeOrQR = 0;
  int _totalBarcodeOrQR = 0;

  final Map<String, Symbology> _symbologies = {
    'Code128 (Barcode)': Code128(),
    'QRCode': QRCode(),
  };

  Future<ui.Image> _captureImage(GlobalKey key) async {
    int attempts = 0;
    const maxAttempts = 5;
    const delay = Duration(milliseconds: 300);

    while (attempts < maxAttempts) {
      try {
        final context = key.currentContext;
        if (context == null) {
          await Future.delayed(delay);
          attempts++;
          continue;
        }

        final boundary = context.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null || boundary.debugNeedsPaint) {
          await Future.delayed(delay);
          attempts++;
          continue;
        }

        return await boundary.toImage(pixelRatio: 3.0);
      } catch (_) {
        await Future.delayed(delay);
        attempts++;
      }
    }

    throw Exception('Failed to capture image after $maxAttempts attempts');
  }

  late Symbology _selectedSymbology = _symbologies['Code128 (Barcode)']!;

  Future<void> _waitUntilRendered(GlobalKey key) async {
    int retries = 0;
    const maxRetries = 10;
    while (retries < maxRetries) {
      final context = key.currentContext;
      final renderObject = context?.findRenderObject();
      if (context != null &&
          renderObject is RenderRepaintBoundary &&
          !renderObject.debugNeedsPaint) {
        return;
      }
      await Future.delayed(Duration(milliseconds: 100));
      retries++;
    }
  }


  Future<void> _generatePDF({required bool isPrint}) async {
    if (_dataList.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No data to generate PDF.')));
      return;
    }

    setState(() => _isGeneratingPDF = true);

    try {
      // ✅ Load font assets properly for all platforms
      final fontRegularBytes = (await rootBundle.load(
        'assets/fonts/Roboto/static/Roboto-Regular.ttf',
      )).buffer.asUint8List();
      final fontBoldBytes = (await rootBundle.load(
        'assets/fonts/Roboto/static/Roboto-Bold.ttf',
      )).buffer.asUint8List();

      // 🔧 FIXED: Ensure we have the same number of images as data
      final List<Map<String, dynamic>> payload = List.generate(
        _dataList.length,
            (i) {
          return {
            'index': '${(i + 1)}.',
            'data': _dataList[i],
            'base64': (i < _base64Images.length && _base64Images[i].isNotEmpty)
                ? _base64Images[i]
                : '',
          };
        },
      );

      print('🔍 Debug: Creating PDF payload with ${payload.length} items');
      for (int i = 0; i < payload.length; i++) {
        final hasImage = payload[i]['base64'].toString().isNotEmpty;
        print('Item ${i + 1}: "${payload[i]['data']}" - Image: ${hasImage ? "✅" : "❌"}');
      }

      // ✅ Background PDF creation using isolate - FIXED PAGINATION LOGIC
      final pdfBytes = await compute(
            (Map<String, dynamic> params) async {
          final fontBytes = params['fontRegular'] as Uint8List;
          final fontBoldBytes = params['fontBold'] as Uint8List;
          final rawDataList = params['dataList'] as List<dynamic>;

          final pdf = pw.Document();
          final fontRegular = pw.Font.ttf(ByteData.view(fontBytes.buffer));
          final fontBold = pw.Font.ttf(ByteData.view(fontBoldBytes.buffer));
          const itemsPerPage = 10;
          final dataList = rawDataList.cast<Map<String, dynamic>>();

          // 🔧 FIXED: Calculate total pages needed
          final totalPages = (dataList.length / itemsPerPage).ceil();

          print('📊 PDF Info: ${dataList.length} items, $totalPages pages, $itemsPerPage items per page');

          // 🔧 FIXED: Use proper page iteration
          for (int pageNumber = 0; pageNumber < totalPages; pageNumber++) {
            final startIndex = pageNumber * itemsPerPage;
            final endIndex = (startIndex + itemsPerPage > dataList.length)
                ? dataList.length
                : startIndex + itemsPerPage;

            final pageItems = dataList.sublist(startIndex, endIndex);

            print('📄 Page ${pageNumber + 1}: Items ${startIndex + 1} to $endIndex (${pageItems.length} items)');

            pdf.addPage(
              pw.Page(
                pageFormat: PdfPageFormat.a4,
                build: (context) => pw.Container(
                  padding: pw.EdgeInsets.zero,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Header
                      pw.Container(
                        height: 40,
                        width: double.infinity,
                        color: PdfColor.fromHex('#4472C4'),
                        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: pw.Row(
                          children: [
                            pw.Container(
                              width: 60,
                              child: pw.Text(
                                'Index',
                                style: pw.TextStyle(
                                  font: fontBold,
                                  color: PdfColors.white,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            pw.Container(
                              width: 180,
                              child: pw.Text(
                                'Input Data',
                                style: pw.TextStyle(
                                  font: fontBold,
                                  color: PdfColors.white,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            pw.Expanded(
                              child: pw.Text(
                                'Barcode / QR Image',
                                style: pw.TextStyle(
                                  font: fontBold,
                                  color: PdfColors.white,
                                  fontSize: 10,
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(height: 4),

                      // Data rows
                      ...pageItems.asMap().entries.map((entry) {
                        final itemIndex = entry.key;
                        final item = entry.value;
                        final actualIndex = startIndex + itemIndex + 1;

                        final base64Str = item['base64']?.toString() ?? '';

                        pw.Widget image;
                        try {
                          if (base64Str.isNotEmpty) {
                            final imageBytes = base64Decode(base64Str);
                            image = pw.Container(
                              width: 180,
                              height: 60,
                              child: pw.Image(
                                pw.MemoryImage(imageBytes),
                                fit: pw.BoxFit.contain,
                              ),
                            );
                          } else {
                            image = pw.Container(
                              width: 180,
                              height: 60,
                              decoration: pw.BoxDecoration(
                                border: pw.Border.all(color: PdfColors.red),
                              ),
                              child: pw.Center(
                                child: pw.Text(
                                  'No Image',
                                  style: pw.TextStyle(
                                    font: fontRegular,
                                    color: PdfColors.red,
                                    fontSize: 8,
                                  ),
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          image = pw.Container(
                            width: 180,
                            height: 60,
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(color: PdfColors.red),
                            ),
                            child: pw.Center(
                              child: pw.Text(
                                'Image Error',
                                style: pw.TextStyle(
                                  font: fontRegular,
                                  color: PdfColors.red,
                                  fontSize: 8,
                                ),
                              ),
                            ),
                          );
                        }

                        return pw.Container(
                          margin: const pw.EdgeInsets.only(bottom: 2),
                          padding: const pw.EdgeInsets.all(2),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColors.grey300),
                          ),
                          child: pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Container(
                                width: 60,
                                child: pw.Text(
                                  '$actualIndex.',
                                  style: pw.TextStyle(
                                    font: fontRegular,
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                              pw.Container(
                                width: 180,
                                child: pw.Text(
                                  item['data']?.toString() ?? '',
                                  style: pw.TextStyle(
                                    font: fontRegular,
                                    fontSize: 9,
                                  ),
                                  maxLines: 3,
                                  overflow: pw.TextOverflow.clip,
                                ),
                              ),
                              pw.SizedBox(width: 10),
                              image,
                            ],
                          ),
                        );
                      }).toList(),

                      // Spacer to push footer down
                      pw.Spacer(),

                      // Footer
                      pw.Container(
                        padding: const pw.EdgeInsets.only(top: 2),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          children: [
                            pw.Text(
                              'Page ${pageNumber + 1} of $totalPages',
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: 8,
                                color: PdfColors.grey600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          print('✅ PDF generated with $totalPages pages for ${dataList.length} items');
          return pdf.save();
        },
        {
          'fontRegular': fontRegularBytes,
          'fontBold': fontBoldBytes,
          'dataList': payload,
        },
      );

      if (!isPrint) {
        // ✅ SAVE DIALOG works everywhere
        final now = DateTime.now();
        final isMobile = Platform.isAndroid || Platform.isIOS;

        final filePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save PDF File',
          fileName: 'barcodes_output_${now.millisecondsSinceEpoch}.pdf',
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          bytes: isMobile ? pdfBytes : null, // ✅ Required on Android/iOS
        );

        if (filePath == null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('PDF save cancelled')));
        } else {
          if (!isMobile) {
            final file = File(filePath);
            await file.writeAsBytes(pdfBytes);
          }

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('PDF saved successfully!')));
        }
      } else {
        try {
          await Printing.layoutPdf(
            onLayout: (PdfPageFormat format) async => pdfBytes,
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Printing not supported on this platform: $e"),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ PDF Generation Error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error generating PDF: $e')));
    } finally {
      setState(() => _isGeneratingPDF = false);
    }
  }

  Future<void> _generate() async {
    if (dataController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter some data to generate barcodes / QR codes'),
        ),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      final rawText = dataController.text;
      final separator = separatorController.text == '\\n' ? '\n' : separatorController.text;
      _dataList = rawText
          .split(separator)
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      _barcodeKeys.clear();
      _barcodeKeys.addAll(List.generate(_dataList.length, (_) => GlobalKey()));
      _base64Images.clear();
      _barcodeData.clear();
    });

    print('🚀 Starting barcode generation for ${_dataList.length} items');

    // Allow the UI to rebuild before capturing
    await Future.delayed(const Duration(milliseconds: 500));

    Future<void> _waitUntilRendered(GlobalKey key) async {
      int retries = 0;
      const maxRetries = 15; // Increased retries
      while (retries < maxRetries) {
        final context = key.currentContext;
        final renderObject = context?.findRenderObject();
        if (context != null &&
            renderObject is RenderRepaintBoundary &&
            !renderObject.debugNeedsPaint) {
          return;
        }
        await Future.delayed(const Duration(milliseconds: 100));
        retries++;
      }
      throw Exception('Widget not rendered after $maxRetries attempts');
    }

    Future<ui.Image> _captureImage(GlobalKey key) async {
      int attempts = 0;
      const maxAttempts = 8; // Increased attempts
      const delay = Duration(milliseconds: 200); // Reduced delay

      while (attempts < maxAttempts) {
        try {
          final context = key.currentContext;
          if (context == null) {
            print('  ⏳ Attempt ${attempts + 1}: Context is null, waiting...');
            await Future.delayed(delay);
            attempts++;
            continue;
          }

          final boundary = context.findRenderObject() as RenderRepaintBoundary?;
          if (boundary == null) {
            print('  ⏳ Attempt ${attempts + 1}: Boundary is null, waiting...');
            await Future.delayed(delay);
            attempts++;
            continue;
          }

          if (boundary.debugNeedsPaint) {
            print('  ⏳ Attempt ${attempts + 1}: Boundary needs paint, waiting...');
            await Future.delayed(delay);
            attempts++;
            continue;
          }

          print('  ✅ Attempt ${attempts + 1}: Capturing image...');
          return await boundary.toImage(pixelRatio: 3.0);
        } catch (e) {
          print('  ❌ Attempt ${attempts + 1}: Error capturing image: $e');
          await Future.delayed(delay);
          attempts++;
        }
      }

      throw Exception('Failed to capture image after $maxAttempts attempts');
    }

    try {
      // Process barcodes sequentially for better reliability
      for (var i = 0; i < _barcodeKeys.length; i++) {
        print('📱 Processing barcode ${i + 1}/${_dataList.length}: "${_dataList[i]}"');

        try {
          // Wait for the widget to be rendered
          await _waitUntilRendered(_barcodeKeys[i]);

          // Add a small delay for mobile devices
          if (Platform.isAndroid || Platform.isIOS) {
            await Future.delayed(const Duration(milliseconds: 150));
          }

          // Capture the image
          final image = await _captureImage(_barcodeKeys[i]);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

          String base64String = '';
          if (byteData != null) {
            base64String = base64Encode(byteData.buffer.asUint8List());
            print('  ✅ Image captured: ${base64String.length} bytes');
          } else {
            print('  ⚠️ Byte data is null for barcode $i');
          }

          _base64Images.add(base64String);
          _barcodeData.add({
            'data': _dataList[i],
            'base64': base64String,
            'index': (i + 1).toString(),
          });

          setState(() {
            barcodes = i + 1;
            barcodesText = 'Generated barcode ${i + 1}/${_dataList.length}';
            _generatedBarcodeOrQR = i + 1;
            _totalBarcodeOrQR = _dataList.length;
          });

          // Additional delay for mobile devices
          if (Platform.isAndroid || Platform.isIOS) {
            await Future.delayed(const Duration(milliseconds: 100));
          }

        } catch (e) {
          print('❌ Failed to generate barcode $i: $e');
          _base64Images.add('');
          _barcodeData.add({
            'data': _dataList[i],
            'base64': '',
            'index': (i + 1).toString(),
          });
        }
      }

      // 🔧 FIXED: Call _printBarcodeInfo AFTER all barcodes are generated
      _printBarcodeInfo();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Generated ${_base64Images.where((img) => img.isNotEmpty).length}/${_base64Images.length} barcodes successfully.')),
      );
    } catch (e) {
      print('❌ Exception during generation: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating barcodes: $e')),
      );
    }

    setState(() {
      _isGenerating = false;
    });
  }

  Future<void> _generateExcelFile() async {
    try {
      // Create a new workbook ONCE
      Workbook workbook = Workbook();
      Worksheet sheet = workbook.worksheets[0];

      // Set headers
      sheet.getRangeByName('A1').setText('Index');
      sheet.getRangeByName('B1').setText('Input Data');
      sheet.getRangeByName('C1').setText('Barcode / QR Image');

      // Style headers
      Range headerRange = sheet.getRangeByName('A1:C1');
      headerRange.cellStyle.bold = true;
      headerRange.cellStyle.backColor = '#4472C4';
      headerRange.cellStyle.fontColor = '#FFFFFF';

      // Set column widths
      sheet.setColumnWidthInPixels(1, 100); // Index column
      sheet.setColumnWidthInPixels(2, 200); // Data column
      sheet.setColumnWidthInPixels(3, 300); // Image column

      // Add all data to the Excel file
      for (var i = 0; i < _barcodeData.length; i++) {
        int row = i + 2; // Start from row 2 (after header)

        // Add index
        sheet.getRangeByName('A$row').setNumber(i + 1);

        // Add input data
        sheet.getRangeByName('B$row').setText(_barcodeData[i]['data']!);

        // Add barcode image
        String base64 = _barcodeData[i]['base64']!;
        try {
          // Add image from base64
          Picture picture = sheet.pictures.addBase64(row, 3, base64);
          picture.height = 80; // Set image height
          picture.width = 200; // Set image width

          // Set row height to accommodate image
          sheet.setRowHeightInPixels(row, 90);
        } catch (e) {
          print('Error adding image for row $row: $e');
          // Add text indicating image error
          sheet.getRangeByName('C$row').setText('Image Error');
        }
      }

      // Auto-fit columns (optional)
      sheet.autoFitColumn(1);
      sheet.autoFitColumn(2);

      // save file dialog & get systemcurrentmills
      try {
        print('Attempting to show save file dialog...');
        final now = DateTime.now();

        final List<int> bytes = workbook.saveAsStream();
        final Uint8List uint8Bytes = Uint8List.fromList(bytes);

        // ✅ Pass them to FilePicker (required on mobile)
        String? outputFile = await FilePicker.platform
            .saveFile(
              dialogTitle: 'Save Excel File',
              fileName: 'barcodes_output_${now.millisecondsSinceEpoch}.xlsx',
              type: FileType.custom,
              allowedExtensions: ['xlsx'],
              bytes: uint8Bytes,
            )
            .catchError((error) {
              print('Error in FilePicker: $error');
              return null;
            });

        print('Selected output file path: $outputFile');

        if (outputFile != null) {
          // ✅ Only needed on desktop
          if (!Platform.isAndroid && !Platform.isIOS) {
            print('Saving file to: $outputFile');
            await File(outputFile).writeAsBytes(bytes);
          }

          print('File saved successfully');
          setState(() {
            isExported = true;
          });
        } else {
          print('No file selected or dialog was cancelled');
          setState(() {
            isExported = false;
          });
        }

        workbook.dispose();
      } catch (e) {
        print('Error saving file: $e');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving file: $e')));
      }

      print(
        'Excel file generated successfully with ${_barcodeData.length} records',
      );
    } catch (e) {
      print('Error generating Excel file: $e');
      rethrow;
    }
    isExported
        ? ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Generated ${_base64Images.length} barcodes successfully! Excel file saved.',
              ),
            ),
          )
        : ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Generated barcodes successfully! Excel file not saved.',
              ),
            ),
          );
  }

  // Enhanced method showing comprehensive loops with data and base64
  void _printBarcodeInfo() {
    print('=== 📊 FINAL BARCODE GENERATION SUMMARY ===');
    print('Total data items: ${_dataList.length}');
    print('Total base64 images: ${_base64Images.length}');
    print('Total barcode data objects: ${_barcodeData.length}');

    final successfulImages = _base64Images.where((img) => img.isNotEmpty).length;
    final failedImages = _base64Images.length - successfulImages;
    print('Successful images: $successfulImages');
    print('Failed images: $failedImages');
    print('');

    // Detailed breakdown
    print('📋 DETAILED BREAKDOWN:');
    for (var i = 0; i < _dataList.length; i++) {
      final inputData = _dataList[i];
      final hasBase64 = i < _base64Images.length && _base64Images[i].isNotEmpty;
      final base64Length = i < _base64Images.length ? _base64Images[i].length : 0;

      print('Item ${i + 1}:');
      print('  📝 Data: "$inputData"');
      print('  🖼️  Image: ${hasBase64 ? "✅ Success" : "❌ Failed"}');
      print('  📏 Base64 Length: $base64Length characters');
      if (hasBase64 && base64Length > 50) {
        print('  🔍 Base64 Preview: ${_base64Images[i].substring(0, 50)}...');
      }
      print('  ${"-" * 40}');
    }

    print('=== 🏁 END OF BARCODE GENERATION SUMMARY ===');
  }

  void _copyBarcodeData(String data) {
    Clipboard.setData(ClipboardData(text: data));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$data copied to clipboard!')));
  }

  void _clearAll() {
    setState(() {
      dataController.clear();
      _dataList.clear();
      _base64Images.clear();
      _barcodeKeys.clear();
      _barcodeData.clear();
    });
  }

  /// Converts Excel column letter to index: A => 0, B => 1, ..., Z => 25
  int columnLetterToIndex(String letter) {
    letter = letter.toUpperCase();
    int index = 0;
    for (int i = 0; i < letter.length; i++) {
      index *= 26;
      index += letter.codeUnitAt(i) - 'A'.codeUnitAt(0) + 1;
    }
    return index - 1;
  }

  List<String> _colOrHeader = [];
  List<List<Data?>> _rows = [];
  Excel? _loadedExcel;
  String selectedHeader = '';

  Future<void> _readExcelFileAndShowDialog(BuildContext context) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );

    if (result == null || result.files.single.bytes == null) {
      setState(() {
        dataController.text = '❌ No file selected';
        _colOrHeader = [];
        _rows = [];
        _loadedExcel = null;
      });
      return;
    }

    try {
      Uint8List fileBytes = result.files.single.bytes!;
      _loadedExcel = Excel.decodeBytes(fileBytes);

      if (_loadedExcel!.tables.isEmpty) {
        setState(() {
          dataController.text = '❌ No tables found';
          _colOrHeader = [];
          _rows = [];
          _loadedExcel = null;
        });
        return;
      }

      var table = _loadedExcel!.tables.values.first;
      _rows = table.rows;

      if (_rows.isEmpty) {
        setState(() {
          dataController.text = '❌ Excel is empty';
          _colOrHeader = [];
          _rows = [];
        });
        return;
      }

      // Read header row (first row)
      _colOrHeader = _rows[0]
          .map((cell) => cell?.value?.toString().trim() ?? '')
          .toList();
      selectedHeader = _colOrHeader.isNotEmpty ? _colOrHeader[0] : '';

      // Show selection dialog immediately
      _showHeaderSelectionDialog(context);
    } catch (e) {
      setState(() {
        dataController.text = '❌ Error reading Excel: $e';
        _colOrHeader = [];
        _rows = [];
        _loadedExcel = null;
      });
    }
  }

  bool isNewLine = false;

  void _showHeaderSelectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) {
        return Dialog.fullscreen(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              List<String> columnValues = [];

              void _extractColumn(String header) {
                int colIndex = _colOrHeader.indexOf(header);
                columnValues = [];
                for (int i = 1; i < _rows.length; i++) {
                  if (colIndex < _rows[i].length) {
                    var cell = _rows[i][colIndex];
                    if (cell?.value != null) {
                      columnValues.add(cell!.value.toString());
                    }
                  }
                }
              }

              _extractColumn(selectedHeader);
              return LayoutBuilder(
                builder: (context, constraints) {
                  return SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: Padding(
                      padding: const EdgeInsets.all(35),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select Column to Read',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          DropdownButton<String>(
                            isExpanded: true,
                            value: selectedHeader,
                            icon: const Icon(Icons.table_chart),
                            underline: Container(
                              height: 2,
                              color: Colors.indigo,
                            ),
                            items: _colOrHeader.map((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setDialogState(() {
                                  selectedHeader = newValue;
                                  _extractColumn(newValue);
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Preview:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              child: SelectableText(columnValues.join('\n')),
                            ),
                          ),
                          const SizedBox(height: 16),
                          CheckboxListTile(
                            value: isNewLine,
                            onChanged: (bool? value) {
                              setDialogState(() {
                                isNewLine = value!;
                              });
                            },
                            title: const Text("Use New Line Separator"),
                            subtitle: Text(
                              "If you use New Line Separator it will not change visually in Separator Drop Down",
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () {
                              setDialogState(() {
                                dataController.text = columnValues.join('\n');
                                if (isNewLine) {
                                  separator = separators.first;
                                  separatorController.text = '\\n';
                                  // it is not change visually
                                }
                              });
                              Navigator.of(context).pop();
                            },
                            child: const Text('Read Data Column'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text("Close"),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<String> _readLicense() async {
    try {
      return await rootBundle.loadString('assets/LICENSE.txt');
    } catch (e) {
      return e.toString();
    }
  }

  void _openLicense() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog.fullscreen(
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          child: Column(
            children: [
              const SizedBox(height: 12),
              const Text(
                "LICENSE",
                style: TextStyle(fontSize: 30.0, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: FutureBuilder<String>(
                  future: _readLicense(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return Text('Error: ${snapshot.error}');
                    } else {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: SelectableText(snapshot.data ?? ''),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    var width = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Bulk Barcode Generator"),
        elevation: 2,
        actions: [
          IconButton(
            onPressed: () async {
              await _readExcelFileAndShowDialog(context);
            },
            icon: Icon(Icons.file_open_rounded),
            tooltip: "Import Data Form Excel File",
          ),
          IconButton(
            onPressed: () => _openLicense(),
            icon: Icon(Icons.attach_money),
            tooltip: "LICENSE",
          ),
          _dataList.isNotEmpty
              ? IconButton(
                  onPressed: _clearAll,
                  icon: const Icon(Icons.clear_all),
                  tooltip: 'Clear All',
                )
              : Container(),
          IconButton(
            onPressed: () {
              // Open source code URL in browser
              openLink('https://github.com/asciiblues/bulk_barcode');
            },
            icon: const Icon(Icons.code),
            tooltip: 'Source Code',
          ),
          SizedBox(width: 7.0),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isGenerating || _isGeneratingPDF || _dataList.isEmpty
            ? null
            : () async => await _generatePDF(isPrint: true),
        tooltip: "Print PDF",
        child: Icon(Icons.print),
      ),
      body: Platform.isAndroid || Platform.isIOS
          ? Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: ListView(
                children: [
                  _generateArea(),
                  const SizedBox(height: 16),
                  _results(),
                ],
              ),
            )
          : Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(width: width * 0.55, child: _generateArea()),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: width * 0.41,
                    child: ListView(children: [_results()]),
                  ),
                ],
              ),
            ),
    );
  }

  List<String> separators = <String>[
    'New Line (\\n)',
    'Comma (,)',
    'Semicolon (;)',
    'vertical bar(|)',
    'Space ( )',
    'Custom',
  ];
  String separator = "";

  Widget _generateArea() {
    separator = separators.first;
    setState(() {
      separator == separators.last ? isCustomSprt = true : isCustomSprt = false;
    });
    return Platform.isAndroid || Platform.isIOS
        ? _generateAreaMain()
        : ListView(children: [_generateAreaMain()]);
  }

  Widget _generateAreaMain() {
    var height = MediaQuery.of(context).size.height;
    var colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Input Configuration',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: dataController,
                  decoration: const InputDecoration(
                    labelText: 'Enter Data',
                    hintText:
                        'Enter your data here, separated by the chosen separator\nOr use open excel file to read data',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.data_object),
                  ),
                  maxLines: 5,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField(
                  value: separator,
                  decoration: const InputDecoration(
                    labelText: 'Separator',
                    border: OutlineInputBorder(),
                  ),
                  items: separators.map((String value) {
                    return DropdownMenuItem(value: value, child: Text(value));
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        separator = newValue;
                        switch (newValue) {
                          case 'New Line (\\n)':
                            separatorController.text = "\\n";
                            break;
                          case 'Comma (,)':
                            separatorController.text = ',';
                            break;
                          case 'Semicolon (;)':
                            separatorController.text = ';';
                            break;
                          case 'vertical bar(|)':
                            separatorController.text = '|';
                            break;
                          case 'Space ( )':
                            separatorController.text = ' ';
                            break;
                          default:
                            showDialog(
                              context: context,
                              builder: (_) {
                                return StatefulBuilder(
                                  builder: (context, setInnerState) {
                                    TextEditingController temp_sprt =
                                        TextEditingController();
                                    return AlertDialog(
                                      title: Text("Custom Separator"),
                                      content: SizedBox(
                                        height: height * 0.10,
                                        child: Column(
                                          children: [
                                            TextField(
                                              controller: temp_sprt,
                                              decoration: InputDecoration(
                                                labelText: 'Separator',
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: Text("Cancel"),
                                        ),
                                        FilledButton(
                                          onPressed: () {
                                            if (temp_sprt.text.isNotEmpty) {
                                              setInnerState(() {
                                                separatorController.text =
                                                    temp_sprt.text;
                                                separator = temp_sprt.text;
                                              });
                                            }
                                            Navigator.pop(context);
                                          },
                                          child: Text('Done'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            );
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _symbologies.keys.firstWhere(
                    (key) =>
                        _symbologies[key].runtimeType ==
                        _selectedSymbology.runtimeType,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Barcode / QR',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.qr_code),
                  ),
                  items: _symbologies.keys.map((String key) {
                    return DropdownMenuItem<String>(
                      value: key,
                      child: Text(key),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedSymbology = _symbologies[newValue]!;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        //Generate Button
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed:
                      _dataList.isNotEmpty && _isGenerating || _isGeneratingPDF
                      ? null
                      : _generate,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.qr_code_scanner),
                  label: Text("Generate Barcode(s) / QR code(s)"),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Export Buttons
        Row(
          children: [
            Expanded(
              child: Theme(
                data: ThemeData(
                  colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
                ),
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed:
                        _dataList.isEmpty || _isGenerating || _isGeneratingPDF
                        ? null
                        : _generateExcelFile,
                    icon: _isGenerating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : _getIconExcel(),
                    label: Text("Export to Excel"),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Theme(
                data: ThemeData(
                  colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
                ),
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed:
                        _dataList.isEmpty || _isGenerating || _isGeneratingPDF
                        ? null
                        : () async => await _generatePDF(isPrint: false),
                    icon: _isGenerating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : _isGeneratingPDF
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf),
                    label: Text(
                      _isGeneratingPDF
                          ? "Generating & Exporting / Printing PDF ..."
                          : "Export PDF",
                    ),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_dataList.isNotEmpty) ...[
          SizedBox(height: 7.5),
          Divider(),
          SizedBox(height: 7.5),
          Container(
            decoration: BoxDecoration(color: colorScheme.primaryContainer),
            child: ItemProgressBar(
              current: _generatedBarcodeOrQR,
              total: _totalBarcodeOrQR,
            ),
          ),
        ],
      ],
    );
  }

  Widget _results() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Column(
              children: [
                Text(
                  'Generated Barcodes (${_dataList.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
              ],
            ),
            const SizedBox(height: 16),
            // Using for-in loop to generate the barcode widgets
            ...() {
              List<Widget> barcodeWidgets = [];
              for (var i = 0; i < _dataList.length; i++) {
                barcodeWidgets.add(
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Item ${i + 1}: ${_dataList[i]}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (i < _barcodeData.length)
                              IconButton(
                                onPressed: () => _copyBarcodeData(_dataList[i]),
                                icon: const Icon(Icons.copy, size: 20),
                                tooltip: 'Copy Barcode Data',
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        RepaintBoundary(
                          key: _barcodeKeys[i],
                          child: Container(
                            height: 125,
                            color: Colors.white,
                            padding: const EdgeInsets.all(8),
                            child: SfBarcodeGenerator(
                              value: _dataList[i],
                              symbology: _selectedSymbology,
                              showValue: _showValue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return barcodeWidgets;
            }(),
          ],
        ),
      ),
    );
  }
}

class ItemProgressBar extends StatelessWidget {
  final int current;
  final int total;

  const ItemProgressBar({
    super.key,
    required this.current,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (total == 0) ? 0.0 : current / total;

    return Padding(
      padding: EdgeInsets.all(0.75),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: progress),
            duration: Duration(milliseconds: 375),
            builder: (context, value, child) {
              return LinearProgressIndicator(
                value: value,
                minHeight: 8,
                color: current == total
                    ? Colors.green[800]
                    : Theme.of(context).colorScheme.primary,
              );
            },
          ),
          const SizedBox(height: 3),
          Text(
            '$current / $total',
            style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
          ),
        ],
      ),
    );
  }
}
