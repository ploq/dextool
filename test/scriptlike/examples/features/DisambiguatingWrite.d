import scriptlike;
import std.stdio;

void main()
{
	// Setup and cleanup
	chdir(thisExePath.dirName);
	scope(exit)
		tryRemove("filename.txt");

	// Save file
	//write("filename.txt", "content");  // Error: Symbols conflict!
	// Change line above to...
	writeFile("filename.txt", "content");  // Convenience alias included in scriptlike

	// Output to stdout with no newline
	//write("Hello ", "world");  // Error: Symbols conflict!
	// Change line above to...
	std.stdio.write("Hello ", "world");
	// or...
	stdout.write("Hello ", "world");
}
