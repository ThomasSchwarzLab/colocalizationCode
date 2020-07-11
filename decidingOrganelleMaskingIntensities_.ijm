// Get single channel //
ImageID=getImageID();
if (nSlices>1){
	Stack.getDimensions(width, height, channels, slices, frames);
	if (channels>1){
		channelNumber=getNumber("Enter channel number to use for organelle detection", 1);
		run("Duplicate...", "duplicate channels="+channelNumber);
	}else run("Duplicate...", "duplicate");
} run("Grays");
singleChannelImageID=getImageID();
////////////////////////////////////////////////////
//start of main function /////////////////////////////
//Put this whole thing in a while loop
repeatFlag=1;
while (repeatFlag==1) {
	setBatchMode(true);
	
	// Declare UID for function run //
	getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
	UID=""+dayOfMonth+month+year+"_"+hour+"_"+minute+"_"+second;


	selectImage(singleChannelImageID);
	run("Duplicate...", "duplicate");
	rename("organelleChannel"+UID);
		
	
	// Get thresholding info for organelles //
	Dialog.create("Input Organelle detection parameters");
	Dialog.addNumber("Lower Limit of organelle size (in pixels^2)", 9);
	Dialog.addNumber("Upper Limit of organelle size (in pixels^2)", 3000);
	Dialog.addNumber("Thresholding intensity for detecting organelles", 27);
	Dialog.addMessage("Thresholding is done on a scale of 0-255 \nHigher number indicates more stringent thresholding");
	Dialog.show();
	lowerSizeLimit=Dialog.getNumber();
	upperSizeLimit=Dialog.getNumber();
	organelleIntensity = Dialog.getNumber();
	
	divideLargeParticles=true;
	
	// clear previous ROIs //
	if (isOpen("ROI Manager")){
		selectWindow("ROI Manager");
		run("Close");
		selectWindow("organelleChannel"+UID);
		run("Select None");
	}
	
	// backround substractions //
	selectWindow("organelleChannel"+UID);
	run("Duplicate...", "duplicate channels=1");
	rename ("organelleMaskChannel"+UID);
	run("Set Scale...", "distance=0 known=0 pixel=1 unit=pixel");
	run("Subtract Background...", "rolling="+lowerSizeLimit*2+" stack");
	
	// getting display range with 0.35% saturation//
	selectWindow("organelleMaskChannel"+UID);
	run("Z Project...", "projection=[Max Intensity]"); 
	resetMinAndMax(); run("Enhance Contrast", "saturated=0.35"); getMinAndMax(min, max); close();

	// copy entire image into a large 1D array // this drastically increases spped of contrast enhancement and thresholding //
	

	
	// setting display range //
	getDimensions(width, height, channels, slices, frames); slices=slices*frames*channels; 
	imageBitDepth=bitDepth(); maxPossibleIntensity=pow(2, imageBitDepth)-1;
	
	IJ.log("Please wait ... Stretching contrast\n  "); selectWindow("organelleMaskChannel"+UID);  
	for (z = 0; z < slices; z++) {setSlice(z+1);  print("\\Update:"+(z/slices*100)); // updating progress
		for (x = 0; x < width; x++) {	for (y = 0; y < height; y++) { 
			intensity=getPixel(x, y);
			if (intensity<min) {setPixel(x, y, min);} // any pixel less than min is equal to min
			if (intensity>max) {setPixel(x, y, max);} // Any pixel more than max is equal to max
			intensity=(intensity-min)/max*maxPossibleIntensity; // stretching pixels from 0 to max
			setPixel(x, y, intensity);
		}	}	} selectWindow("Log"); run("Close");
	
	// thresholding //
	IJ.log("Please wait ... Thresholding\n  "); selectWindow("organelleMaskChannel"+UID); 
	resetMinAndMax; run("8-bit"); // setting image to 8-bit
	for (z = 0; z < slices; z++) {setSlice(z+1); print("\\Update:"+(z/slices*100)); // updating progress
		for (x = 0; x < width; x++) { for (y = 0; y < height; y++) { 
			if (getPixel(x, y)<organelleIntensity) {setPixel(x, y, 0); // if pixel less than threshold, then set it to zero
			} else {setPixel(x, y, 255); }   // else set it to 255
			}	}   } selectWindow("Log"); run("Close");
	run("Remove Outliers...", "radius=3 threshold=0 which=Bright stack");
	
	// detecting particles //
	run("Analyze Particles...", "clear include add stack");
	
	// removing small particles //
	run("Select None");
	numberOfPoints=roiManager("count");
	for (pointNumber=0; pointNumber<numberOfPoints; pointNumber++){
		roiManager("select", pointNumber);
		getRawStatistics(nPixels, mean, min, max, std, histogram);
		if (nPixels<lowerSizeLimit){
			run("Clear", "slice");
		}
	}
	
	// re-detecting particles //
	run("Select None"); roiManager("reset");
	run("Analyze Particles...", "clear include add stack");
	
	
	
	// Eroding to split up large particles (but only if the full particle doesnt dissappear //
	if (divideLargeParticles==true){
		IJ.log("Please wait ... Breaking up large particles\n  ");
		for (erodingIteration = 0; erodingIteration < 100; erodingIteration++) { // repeat erosion 100 times
			print("\\Update:"+erodingIteration); // updating progress
			//at every repeat find particles larger than upper size limit and erode them
			run("Select None"); roiManager("reset"); run("Analyze Particles...", "clear include add stack"); // re-detecting particles //
			for (pointNumber=0; pointNumber<roiManager("count"); pointNumber++){ // going through particle
				roiManager("select", pointNumber); getRawStatistics(nPixels, mean, min, max, std, histogram);
				if (nPixels> upperSizeLimit){run("Options...", "iterations=1 count=1 black do=Erode");} // eroding large objects
			} 	} selectWindow("Log"); run("Close");
		// Enlarging selections in case they are too small //
		IJ.log("Please wait ... expanding all particles by 1 px\n  ");
		for (pointNumber=0; pointNumber<roiManager("count"); pointNumber++){
			print("\\Update:"+pointNumber/roiManager("count")*100); // updating progress
			roiManager("select", pointNumber);run("Enlarge...", "enlarge=1");}
	} selectWindow("Log"); run("Close");
		
	roiManager("Show None");
	
	
	
	// Rice coloring all the organelles found //
	selectWindow("organelleMaskChannel"+UID); run("RGB Color");
	IJ.log("Please wait ... Coloring all particles\n  ");
	for (pointNumber=0; pointNumber<roiManager("count"); pointNumber++){
		print("\\Update:"+pointNumber/roiManager("count")*100); // updating progress
		roiManager("select", pointNumber); 
		setForegroundColor(round(random*255), round(random*255), round(random*255));
		run("Fill", "slice");
	}selectWindow("Log"); run("Close");
	
	// Concatenating original and thresholded images //
	selectWindow("organelleChannel"+UID); run("RGB Color");
	run("Combine...", "stack1=organelleChannel"+UID+" stack2=organelleMaskChannel"+UID);
	rename("maskAndRawImageCombined"+UID);

	setBatchMode(false);

	// asking user to scroll through the combined image and satisfaction //
	setLocation(0, 0, getWidth(), getHeight());
	Dialog.createNonBlocking("Is the thresholding okay?");
	Dialog.addRadioButtonGroup("", newArray("Thresholding is good", "Repeat thresholding"), 2, 1, "Thresholding is good");
	Dialog.show();
	if (endsWith(Dialog.getRadioButton(), "Thresholding is good")){repeatFlag=0;}
	selectWindow("maskAndRawImageCombined"+UID); close();
}
selectImage(singleChannelImageID); close();