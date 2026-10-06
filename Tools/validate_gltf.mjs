// Validates glTF / GLB files with the Khronos glTF Validator (CI's interop job: painted exports must be clean).
//
//     npm install --no-save gltf-validator@2.0.0-dev.3.10
//     node Tools/validate_gltf.mjs acceptance/painted/painted.glb
import { readFileSync } from "node:fs";
import validator from "gltf-validator";

const severities = ["ERROR", "WARNING", "INFO", "HINT"];
let failed = false;
for (const file of process.argv.slice(2)) {
    const report = await validator.validateBytes(new Uint8Array(readFileSync(file)), { uri: file, maxIssues: 50 });
    const { numErrors, numWarnings, messages } = report.issues;
    for (const message of messages) {
        console.log(`${severities[message.severity]} ${message.code} ${message.pointer ?? ""} ${message.message}`);
    }
    console.log(`${file}: ${numErrors} errors, ${numWarnings} warnings`);
    if (numErrors > 0) failed = true;
}
process.exit(failed ? 1 : 0);
