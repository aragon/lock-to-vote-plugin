/**
 * @main
 * This Deno script uploads a specified file to Pinata using the API
 * and prints the resulting IPFS CID (Content Identifier) to the console.
 *
 * @howto
 * 1. Make sure you have Deno installed (https://deno.land/).
 * 2. Create a `.env` file in the same directory as this script.
 * 3. Add your Pinata JWT to the `.env` file: `PINATA_JWT="..."`
 * 4. Run the script from your terminal, providing the path to the file you want to upload:
 * deno run --allow-read --allow-env --allow-net=api.pinata.cloud script/ipfs-pin.ts ./path/to/your/file.json
 */

import { load } from "https://deno.land/std@0.224.0/dotenv/mod.ts";
import { basename } from "https://deno.land/std@0.224.0/path/mod.ts";

const PINATA_API_URL = "https://api.pinata.cloud/pinning/pinFileToIPFS";

/**
 * Validates that the required environment variables are present.
 * @returns The Pinata JWT.
 * @throws {Error} if the PINATA_JWT is not set in the environment.
 */
async function getPinataJwt(): Promise<string> {
  const env = await load({ allowEmptyValues: true });
  const pinataJwt = env["PINATA_JWT"] || Deno.env.get("PINATA_JWT");

  if (!pinataJwt) {
    console.error(
      "Error: Pinata JWT not found. Please create a .env file and add your PINATA_JWT.",
    );
    throw new Error("PINATA_JWT environment variable is not set.");
  }
  return pinataJwt;
}

/**
 * Uploads a file to Pinata.
 * @param filePath - The local path to the file to be uploaded.
 * @param jwt - The Pinata JWT for authentication.
 * @returns The IPFS hash (CID) of the uploaded file.
 * @throws {Error} if the upload fails or the API returns an error.
 */
async function uploadFileToPinata(
  filePath: string,
  jwt: string,
): Promise<string> {
  try {
    // Read the file as a byte array
    const fileBytes = await Deno.readFile(filePath);
    const fileBlob = new Blob([fileBytes], {
      type: `application/octet-stream`,
    });

    // Create a FormData object to send in the request
    const formData = new FormData();
    const fileName = basename(filePath);
    formData.append("file", fileBlob, fileName);

    // Make the POST request to the Pinata API
    const response = await fetch(PINATA_API_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${jwt}`,
      },
      body: formData,
    });

    if (!response.ok) {
      const errorBody = await response.text();
      throw new Error(
        `HTTP error ${response.status}: Failed to upload file. Response: ${errorBody}`,
      );
    }

    const result = await response.json();

    if (result.IpfsHash) {
      return result.IpfsHash;
    } else {
      throw new Error("API response did not include an IpfsHash.");
    }
  } catch (error) {
    console.error(`An error occurred during the upload process.`);
    // Re-throw the error to be caught by the main execution block
    throw error;
  }
}

/**
 * Main execution function.
 */
async function main() {
  // Get the file path from command-line arguments
  const filePath = Deno.args[0];
  if (!filePath) {
    console.error(
      "Error: Please provide a file path as a command-line argument.",
    );
    console.error(
      "Usage: deno run --allow-read --allow-env --allow-net script/ipfs-pin.ts <path/to/file>",
    );
    Deno.exit(1);
  }

  try {
    // Get the Pinata JWT from environment variables
    const jwt = await getPinataJwt();

    // Upload the file and get the CID
    const cid = await uploadFileToPinata(filePath, jwt);

    // Show the result
    console.log(cid);
  } catch (error) {
    console.error("\nOperation failed:", error.message);
    Deno.exit(1);
  }
}

// Run the main function
if (import.meta.main) {
  main();
}
