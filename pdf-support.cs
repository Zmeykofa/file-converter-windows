using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Text;

public static class ConverterPdf
{
    private const string Dll = "pdfiumlo.dll";
    private static readonly object Sync = new object();
    private static IntPtr library;

    public static void Convert(string dllPath, string source, string destination, bool images)
    {
        lock (Sync)
        {
            if (library == IntPtr.Zero)
            {
                library = LoadLibraryEx(dllPath, IntPtr.Zero, 0x1100);
                if (library == IntPtr.Zero)
                    throw new InvalidOperationException("Не удалось загрузить компонент PDF.");
            }

            byte[] bytes = File.ReadAllBytes(source);
            GCHandle buffer = GCHandle.Alloc(bytes, GCHandleType.Pinned);
            try
            {
                FPDF_InitLibrary();
                try
                {
                    IntPtr document = FPDF_LoadMemDocument64(buffer.AddrOfPinnedObject(), (UIntPtr)bytes.Length, IntPtr.Zero);
                    if (document == IntPtr.Zero)
                        throw new InvalidDataException("Не удалось открыть PDF. Возможно, файл повреждён или защищён паролем.");
                    try
                    {
                        int pages = FPDF_GetPageCount(document);
                        if (pages < 1) throw new InvalidDataException("В PDF нет страниц.");
                        if (images)
                            WriteImages(document, pages, destination);
                        else
                            WriteText(document, pages, destination);
                    }
                    finally { FPDF_CloseDocument(document); }
                }
                finally { FPDF_DestroyLibrary(); }
            }
            finally { buffer.Free(); }
        }
    }

    private static void WriteText(IntPtr document, int pages, string destination)
    {
        bool foundText = false;
        using (var output = new StreamWriter(destination, false, new UTF8Encoding(true)))
        {
            for (int index = 0; index < pages; index++)
            {
                IntPtr page = OpenPage(document, index);
                try
                {
                    IntPtr textPage = FPDFText_LoadPage(page);
                    if (textPage == IntPtr.Zero) throw new InvalidDataException("Не удалось прочитать текст страницы.");
                    try
                    {
                        int count = FPDFText_CountChars(textPage);
                        if (count < 0) throw new InvalidDataException("Не удалось прочитать текст страницы.");
                        if (count == 0) continue;
                        byte[] characters = new byte[checked(2 * (count + 1))];
                        int written = FPDFText_GetText(textPage, 0, count, characters);
                        if (written <= 1) continue;
                        string text = Encoding.Unicode.GetString(characters, 0, (written - 1) * 2);
                        if (String.IsNullOrWhiteSpace(text)) continue;
                        if (foundText) output.WriteLine();
                        output.WriteLine(text);
                        foundText = true;
                    }
                    finally { FPDFText_ClosePage(textPage); }
                }
                finally { FPDF_ClosePage(page); }
            }
        }
        if (!foundText)
            throw new InvalidDataException("В PDF нет извлекаемого текста. Для скана можно выбрать «В ZIP (страницы PNG)».");
    }

    private static void WriteImages(IntPtr document, int pages, string destination)
    {
        using (var stream = File.Create(destination))
        using (var zip = new ZipArchive(stream, ZipArchiveMode.Create))
        {
            for (int index = 0; index < pages; index++)
            {
                IntPtr page = OpenPage(document, index);
                try
                {
                    float pageWidth = FPDF_GetPageWidthF(page);
                    float pageHeight = FPDF_GetPageHeightF(page);
                    if (!(pageWidth > 0 && pageHeight > 0))
                        throw new InvalidDataException("Некорректный размер страницы PDF.");
                    double scale = Math.Min(150.0 / 72, 4096.0 / Math.Max(pageWidth, pageHeight));
                    int width = Math.Max(1, (int)Math.Ceiling(pageWidth * scale));
                    int height = Math.Max(1, (int)Math.Ceiling(pageHeight * scale));
                    using (var image = new Bitmap(width, height, PixelFormat.Format32bppRgb))
                    {
                        var data = image.LockBits(new Rectangle(0, 0, width, height), ImageLockMode.WriteOnly, image.PixelFormat);
                        try
                        {
                            IntPtr bitmap = FPDFBitmap_CreateEx(width, height, 3, data.Scan0, data.Stride);
                            if (bitmap == IntPtr.Zero) throw new InvalidOperationException("Не удалось создать изображение страницы.");
                            try
                            {
                                FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xffffffff);
                                FPDF_RenderPageBitmap(bitmap, page, 0, 0, width, height, 0, 1);
                            }
                            finally { FPDFBitmap_Destroy(bitmap); }
                        }
                        finally { image.UnlockBits(data); }
                        var entry = zip.CreateEntry(String.Format("page-{0:D4}.png", index + 1), CompressionLevel.NoCompression);
                        using (var png = new MemoryStream())
                        using (var output = entry.Open())
                        {
                            image.Save(png, ImageFormat.Png);
                            png.Position = 0;
                            png.CopyTo(output);
                        }
                    }
                }
                finally { FPDF_ClosePage(page); }
            }
        }
    }

    private static IntPtr OpenPage(IntPtr document, int index)
    {
        IntPtr page = FPDF_LoadPage(document, index);
        if (page == IntPtr.Zero) throw new InvalidDataException("Не удалось открыть страницу " + (index + 1) + ".");
        return page;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
    [DllImport(Dll)] private static extern void FPDF_InitLibrary();
    [DllImport(Dll)] private static extern void FPDF_DestroyLibrary();
    [DllImport(Dll)] private static extern IntPtr FPDF_LoadMemDocument64(IntPtr bytes, UIntPtr size, IntPtr password);
    [DllImport(Dll)] private static extern int FPDF_GetPageCount(IntPtr document);
    [DllImport(Dll)] private static extern IntPtr FPDF_LoadPage(IntPtr document, int index);
    [DllImport(Dll)] private static extern void FPDF_CloseDocument(IntPtr document);
    [DllImport(Dll)] private static extern void FPDF_ClosePage(IntPtr page);
    [DllImport(Dll)] private static extern float FPDF_GetPageWidthF(IntPtr page);
    [DllImport(Dll)] private static extern float FPDF_GetPageHeightF(IntPtr page);
    [DllImport(Dll)] private static extern IntPtr FPDFText_LoadPage(IntPtr page);
    [DllImport(Dll)] private static extern int FPDFText_CountChars(IntPtr textPage);
    [DllImport(Dll)] private static extern int FPDFText_GetText(IntPtr textPage, int start, int count, [Out] byte[] text);
    [DllImport(Dll)] private static extern void FPDFText_ClosePage(IntPtr textPage);
    [DllImport(Dll)] private static extern IntPtr FPDFBitmap_CreateEx(int width, int height, int format, IntPtr buffer, int stride);
    [DllImport(Dll)] private static extern void FPDFBitmap_FillRect(IntPtr bitmap, int left, int top, int width, int height, uint color);
    [DllImport(Dll)] private static extern void FPDFBitmap_Destroy(IntPtr bitmap);
    [DllImport(Dll)] private static extern void FPDF_RenderPageBitmap(IntPtr bitmap, IntPtr page, int x, int y, int width, int height, int rotation, int flags);
}