<?php
// Patch Shaarli's PublishController to add backup trigger on bookmark save
$file = '/var/www/shaarli/application/front/controller/admin/ShaarePublishController.php';
$code = file_get_contents($file);

// Find the save method and add a touch call before the closing brace
$target = 'public function save(Request $request, Response $response): Response';
if (strpos($code, $target) === false) {
    echo "WARNING: save method not found in ShaarePublishController\n";
    echo "CHECKING: available methods:\n";
    preg_match_all('/function (\w+)/', $code, $matches);
    foreach ($matches[1] as $m) echo "  - $m\n";
    exit(1);
}
if (strpos($code, $target) === false) {
    echo "WARNING: save method not found in ShaarePublishController\n";
    exit(1);
}

// Find the closing brace of the save method and add touch before it
// We look for the last '}' that closes the method (assumes proper indentation)
$pos = strpos($code, $target);
$depth = 0;
$found = false;
$method_end = $pos;
for ($i = $pos; $i < strlen($code); $i++) {
    if ($code[$i] == '{') $depth++;
    if ($code[$i] == '}') {
        $depth--;
        if ($depth == 0) {
            $method_end = $i;
            $found = true;
            break;
        }
    }
}
if (!$found) {
    echo "WARNING: could not find method body end\n";
    exit(1);
}

// Insert the trigger before the closing brace
$trigger = "\n        @touch('/tmp/shaarli-backup-trigger');\n    ";
$code = substr_replace($code, $trigger . substr($code, $method_end), $method_end, 0);

file_put_contents($file, $code);
echo "Patched save() with backup trigger OK\n";
