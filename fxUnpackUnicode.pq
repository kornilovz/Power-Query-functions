(packed as text) as any =>
let
    InputJS =
        Text.Replace(
            Text.FromBinary(
                Json.FromValue(packed),
                TextEncoding.Utf8
            ),
            "<",
            "\u003c"
        ),

    JS = "
function val(c) {
    if (c >= 0x3400 && c <= 0x4cff) {
        return c - 0x3400;
    }

    if (c >= 0x4e00 && c <= 0x9eff) {
        return c - 0x4e00 + 6400;
    }

    if (c >= 0xac00 && c <= 0xc1ff) {
        return c - 0xac00 + 27136;
    }

    throw new Error('Invalid character');
}

function dec(s) {
    var p = s.charCodeAt(0) - 65;
    var b = 0, n = 0, o = [], i, v, k, x;

    if (!s.length || p < 0 || p > 14 ||
        (s.length === 1 && p !== 0)) {
        throw new Error('Invalid header');
    }

    for (i = 1; i < s.length; i++) {
        v = val(s.charCodeAt(i));
        k = i === s.length - 1 ? 15 - p : 15;

        if (i === s.length - 1 && p) {
            if ((v & ((1 << p) - 1)) !== 0) {
                throw new Error('Invalid padding');
            }

            v >>>= p;
        }

        b = (b << k) | v;
        n += k;

        while (n >= 8) {
            n -= 8;
            x = ((b >>> n) & 255).toString(16);
            o.push(x.length === 1 ? '0' + x : x);
            b &= (1 << n) - 1;
        }
    }

    if (n !== 0) {
        throw new Error('Invalid length');
    }

    return o.join('');
}

try {
    document.write(dec(" & InputJS & "));
} catch (e) {
    document.write('ERROR:' + e.message);
}
",

    Page =
        Web.Page(
            "<html><body><script>"
            & JS
            & "</script></body></html>"
        ),

    Data = Page{0}[Data],
    Children = Data{0}[Children],
    BodyChildren = Children{1}[Children],
    ResultText = BodyChildren{1}[Text],

    Hex =
        if Text.StartsWith(ResultText, "ERROR:") then
            error ResultText
        else
            ResultText,

    SourceCode =
        Text.FromBinary(
            Binary.Decompress(
                Binary.FromText(
                    Hex,
                    BinaryEncoding.Hex
                ),
                Compression.Deflate
            ),
            TextEncoding.Utf8
        ),

    RestoredFunction =
        Expression.Evaluate(
            SourceCode,
            #shared
        )
in
    RestoredFunction
