#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

/**
 * Extract ABIs from compiled Foundry output and create separate ABI files
 */
function extractABIs() {
  const projectRoot = path.resolve(__dirname, "..");
  const srcDir = path.join(projectRoot, "src", "protocol");
  const outDir = path.join(projectRoot, "out");
  const abiDir = path.join(projectRoot, "abi");

  // Create abi directory if it doesn't exist
  if (!fs.existsSync(abiDir)) {
    fs.mkdirSync(abiDir, { recursive: true });
    console.log("✓ Created /abi directory");
  }

  // Check if source protocol directory exists
  if (!fs.existsSync(srcDir)) {
    console.error("❌ Source protocol directory not found at:", srcDir);
    process.exit(1);
  }

  // Check if out directory exists
  if (!fs.existsSync(outDir)) {
    console.error("❌ Output directory not found at:", outDir);
    console.log(
      "Please ensure you have compiled your contracts with: forge build"
    );
    process.exit(1);
  }

  let processedCount = 0;
  let errorCount = 0;

  // Function to find compiled contract in out directory
  function findCompiledContract(contractName) {
    // Common patterns for compiled contract locations
    const possiblePaths = [
      path.join(outDir, `${contractName}.sol`, `${contractName}.json`),
      path.join(
        outDir,
        `src/protocol/${contractName}.sol`,
        `${contractName}.json`
      ),
      path.join(outDir, `protocol/${contractName}.sol`, `${contractName}.json`),
    ];

    for (const possiblePath of possiblePaths) {
      if (fs.existsSync(possiblePath)) {
        return possiblePath;
      }
    }

    return null;
  }

  // Function to process a single contract file
  function processContract(compiledPath, contractName) {
    try {
      const contractData = JSON.parse(fs.readFileSync(compiledPath, "utf8"));

      if (!contractData.abi) {
        console.warn(`⚠️  No ABI found in ${contractName}`);
        return false;
      }

      // Create the ABI file with pretty formatting
      const abiFilePath = path.join(abiDir, `${contractName}.json`);
      fs.writeFileSync(abiFilePath, JSON.stringify(contractData.abi, null, 2));

      console.log(`✓ Extracted ABI for ${contractName}`);
      return true;
    } catch (error) {
      console.error(`❌ Error processing ${contractName}:`, error.message);
      errorCount++;
      return false;
    }
  }

  // Recursively scan src/protocol directory for .sol files
  function scanDirectory(dirPath) {
    const items = fs.readdirSync(dirPath);

    for (const item of items) {
      const itemPath = path.join(dirPath, item);
      const stat = fs.statSync(itemPath);

      if (stat.isDirectory()) {
        // Recursively scan subdirectories (like strategies/)
        scanDirectory(itemPath);
      } else if (item.endsWith(".sol")) {
        // This is a Solidity contract file
        const contractName = item.replace(".sol", "");

        // Skip abstract contracts and interfaces (by naming convention)
        if (
          contractName.startsWith("I") ||
          contractName.includes("Storage") ||
          contractName.includes("Abstract")
        ) {
          console.log(
            `⏭️  Skipping interface/abstract contract: ${contractName}`
          );
          continue;
        }

        const compiledPath = findCompiledContract(contractName);

        if (compiledPath) {
          if (processContract(compiledPath, contractName)) {
            processedCount++;
          }
        } else {
          console.warn(`⚠️  Compiled contract not found for: ${contractName}`);
          console.log(
            `   Searched in common output locations for ${contractName}`
          );
        }
      }
    }
  }

  // Start scanning from src/protocol
  scanDirectory(srcDir);

  // Summary
  console.log("\n📊 Summary:");
  console.log(`✅ Successfully processed: ${processedCount} contracts`);
  if (errorCount > 0) {
    console.log(`❌ Errors encountered: ${errorCount}`);
  }
  console.log(`📁 ABI files created in: ${path.resolve(abiDir)}`);

  if (processedCount === 0) {
    console.log("\n💡 Tips:");
    console.log("1. Make sure you have compiled your contracts: forge build");
    console.log(
      "2. Verify that compiled JSON files exist in the out directory"
    );
    console.log("3. Check the Foundry output structure with: ls -la out/");
  }
}

// Run the extraction
console.log("🔄 Extracting ABIs from Foundry compilation output...\n");
extractABIs();
