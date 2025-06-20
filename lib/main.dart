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

  late Symbology _selectedSymbology = _symbologies['Code128 (Barcode)']!;

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

      final List<Map<String, dynamic>> payload = List.generate(
        _dataList.length,
        (i) {
          return {
            'index': '${(i + 1)}.',
            'data': _dataList[i],
            'base64': (_base64Images.length > i) ? _base64Images[i] : '',
          };
        },
      );

      // ✅ Background PDF creation using isolate
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

          for (
            int pageIndex = 0;
            pageIndex < dataList.length;
            pageIndex += itemsPerPage
          ) {
            final pageItems = dataList
                .skip(pageIndex)
                .take(itemsPerPage)
                .toList();

            pdf.addPage(
              pw.Page(
                build: (context) => pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 12,
                  ),
                  child: pw.Column(
                    children: [
                      pw.SizedBox(
                        height: 50,
                        child: pw.Expanded(
                          child: pw.Container(
                            color: PdfColor.fromHex('#4472C4'),
                            child: pw.Row(
                              children: [
                                pw.SizedBox(width: 5),
                                pw.Text(
                                  'Index',
                                  style: pw.TextStyle(
                                    font: fontBold,
                                    color: PdfColors.white,
                                  ),
                                ),
                                pw.SizedBox(width: 20),
                                pw.Text(
                                  'Input Data',
                                  style: pw.TextStyle(
                                    font: fontBold,
                                    color: PdfColors.white,
                                  ),
                                ),
                                pw.Spacer(),
                                pw.Text(
                                  'Barcode / QR Image',
                                  style: pw.TextStyle(
                                    font: fontBold,
                                    color: PdfColors.white,
                                  ),
                                ),
                                pw.SizedBox(width: 60),
                              ],
                            ),
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 10),
                      ...pageItems.map((item) {
                        final base64Str = item['base64'] ?? '';
                        final image = (base64Str.isNotEmpty)
                            ? pw.Image(
                                pw.MemoryImage(base64Decode(base64Str)),
                                height: 80,
                                width: 200,
                              )
                            : pw.Text('Image Error');
                        return pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 4),
                          child: pw.Row(
                            children: [
                              pw.Text(
                                item['index'],
                                style: pw.TextStyle(font: fontRegular),
                              ),
                              pw.SizedBox(width: 20),
                              pw.Expanded(
                                child: pw.Text(
                                  item['data'],
                                  style: pw.TextStyle(font: fontRegular),
                                ),
                              ),
                              pw.SizedBox(width: 20),
                              image,
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
            );
          }

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
          content: Text(
            'Please enter some data to generate barcodes / QR codes',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      final rawText = dataController.text;
      final separator = separatorController.text == '\\n'
          ? '\n'
          : separatorController.text;
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

    // Wait for widgets to build
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      for (var i = 0; i < _barcodeKeys.length; i++) {
        final context = _barcodeKeys[i].currentContext;
        if (context == null) {
          print('⚠️ Context is null for barcode $i, skipping...');
          continue;
        }

        final renderObject = context.findRenderObject();
        if (renderObject is RenderRepaintBoundary) {
          final boundary = renderObject;

          // Fixed: Remove the debugNeedsPaint check as it's causing issues
          // Wait a bit more to ensure rendering is complete
          await Future.delayed(const Duration(milliseconds: 100));

          try {
            int generated = i + 1;
            int total = _dataList.length;
            final image = await boundary.toImage(pixelRatio: 3.0);
            final byteData = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (byteData != null) {
              final base64String = base64Encode(byteData.buffer.asUint8List());
              _base64Images.add(base64String);
              _barcodeData.add({
                'data': _dataList[i],
                'base64': base64String,
                'index': (i + 1).toString(),
              });
              print('✅ Generated barcode $generated/$total');
              setState(() {
                barcodes = i + 1;
                barcodesText = 'Generated barcode ${i + 1}/${_dataList.length}';
                _generatedBarcodeOrQR = generated;
                _totalBarcodeOrQR = total;
              });
            } else {
              print('⚠️ Failed to get byte data for barcode $i');
            }
          } catch (imageError) {
            print('❌ Error converting barcode $i to image: $imageError');
            // Continue with next barcode instead of failing completely
            continue;
          }
        } else {
          print('⚠️ RenderObject is not RenderRepaintBoundary for barcode $i');
        }
      }

      if (_base64Images.isNotEmpty) {
        _printBarcodeInfo(); // Optional logging
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Generated ${_base64Images.length} barcodes successfully!',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No barcodes were generated. Please try again.'),
          ),
        );
      }
    } catch (e, s) {
      print('❌ Exception while generating barcodes: $e\n$s');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error generating barcodes: $e')));
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
    print('=== Barcode Generation Complete ===');
    print('Total barcodes generated: ${_dataList.length}');
    print('');

    // Method 1: Loop using for-in with enumerate-like functionality
    print('Method 1: Using for-in loop with asMap().entries');
    for (var entry in _dataList.asMap().entries) {
      var index = entry.key;
      var inputData = entry.value;
      var base64 = index < _base64Images.length
          ? _base64Images[index]
          : 'Not generated';

      print('Barcode #${index + 1}:');
      print('  Input Data: "$inputData"');
      print('  Base64 Length: ${base64.length} characters');
      print('  Base64: ${base64.substring(0, 50)}...');
      print('  ----------------------------------------');
    }
    print('');

    // List all input data
    print('\nAll Input Data:');
    for (var data in _dataList) {
      print('- "$data"');
    }

    // List all base64 (truncated for readability)
    print('\nAll Base64 Images (first 50 chars):');
    for (var i = 0; i < _base64Images.length; i++) {
      var truncated = _base64Images[i].length > 50
          ? '${_base64Images[i].substring(0, 50)}...'
          : _base64Images[i];
      print('Base64 #${i + 1}: $truncated');
    }

    print('=== END OF BARCODE INFO ===');
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
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: () {
                                  setDialogState(() {
                                    dataController.text = columnValues.join(
                                      '\n',
                                    );
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
                              const SizedBox(width: 12),
                              Expanded(
                                child: CheckboxListTile(
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
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
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
                    label: Text("Export to Excel (XLSX)"),
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
        if(_dataList.isNotEmpty)... [
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
            duration: Duration(milliseconds: 370),
            builder: (context, value, child) {
              return LinearProgressIndicator(
                value: value,
                minHeight: 8,
                color: current == total ? Colors.green[800] : Theme.of(context).colorScheme.primary,
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
