/*  
[INFO] 

NAME = IKEA VR Model QA
VERSION = 1.0.1
AUTHOR = MastaMan
DEV = VISCO
HELP = 

[INSTALL]

MACRO=IKEAVRModelQA
CAT=VISCO
TEXT=KEA VR Model QA
ICON=#("FileLinkActionItems", 5)

[1.0.0]

* First release =

[1.0.1]

+ Added: Show Maps in Viewport button =

[1.0.2]

+ Added: Support nested ColorCorrection for Show Maps in Viewport=

[ABOUT]

This script helps to quickly check errors for selected models.=

Features:=
- Smooth Groups=
- Manifolds=
- Display maps in viewport=
- Statistic=


[TEST]

[SCRIPT]
*/	

fn getScriptInfo s releaseInfo: "" =
(		
	if(releaseInfo != "") do
	(
		r = getINISetting s releaseInfo
		return r
	)
	
	v = getINISetting s "INFO" "VERSION"
	a = getINISetting s "INFO" "AUTHOR"
	n = getINISetting s "INFO" "NAME"
	o = getINISetting s "ABOUT"
	c = getINISetting s "INFO" "DEV"
	h = getINISetting s "INFO" "HELP"
	
	r = for i in (getINISetting s) where i != "ABOUT" and i != "SCRIPT" and i != "COPY" collect i
	
	return #(n, a, v, o, r, c, h)
)

fn parseToLine m = 
(
	if(m.count == 0) do return ""
	
	l = ""				
	for i in m do l += i + "\n"
	return l
)

fn useSettings k p w =
(	
	d = getFilenamePath  (getThisScriptFilename())
	n = filenameFromPath (getThisScriptFilename())			
	settingsFile = d + @"ini\" + (sysInfo.username) + "_" + n + ".ini"
	szUser = sysInfo.computername
	case w of
	(
		"r":
		(
			s = getINISetting settingsFile szUser k
			case p of
			(
				"int": return s as integer
				"float": return s as float
				"bool": if s == "true" then true else false
				default: return s
			)
		)
		default: return setINISetting settingsFile szUser k (p as string)
	)
)

fn checkVray =
(
	for r in RendererClass.classes where matchpattern (r as string) pattern:"*V_Ray_Adv*" do return true		
	return false	
)

fn gw_DrawTriangleCnt =
(
	totalTris = 0
	for i in geometry do
	(
		tris = GetTriMeshFaceCount i
		totalTris += tris[1]
	)
	
	local msg = (totalTris as string) + " Triangles"
	local width = (gw.getWinSizeX() / 2 - 20)
	gw.wText [width, 19, 10] msg color: yellow
)

rollout  _rQACheck "" 
(	
	group "Check Errors" 
	(
		button btnCheckNonManifold "Check Non Maifolds" height: 30 width: 180
		button btnCheckIsolated "Check Isolated Verts" height: 30 width: 180 offset: [0, 10]
		button btnCheckSmoothGroups "Check Missing Smooth Groups" height: 30 width: 180 offset: [0, 10]
	)
	
	group "Textures" 
	(
		button btnShowMapsInVPT "Show Maps in Viewport" height: 30 width: 180		
	)
	
	group "Statistics" 
	(
		checkbox cbxToggleStatistics "  Toggle Statistics" width: 180 height: 30 checked: true
	)
	
	fn showStatistics = 
	(
		unregisterRedrawViewsCallback gw_DrawTriangleCnt
		if(cbxToggleStatistics.checked) do registerRedrawViewsCallback gw_DrawTriangleCnt
		forceCompleteRedraw()
	)
	
	fn getDiffuseColorCorrection d = 
	(
		o = d.map
				
		while o != undefined and hasProperty o "map" do (	
			if(o.map == undefined) then exit
			o = o.map				
		)
			
		if(o == undefined) do return d
		return o
	)
	
	on btnShowMapsInVPT pressed do
	(		
		if(checkVray() == false) do return messageBox "Please assing V-Ray renderer!" title: "Warning"
		
		for m in getClassInstances VrayMtl where m != undefined and  m.texmap_diffuse != undefined do (
								
			tex = case classOf m.texmap_diffuse of (
				Color_Correction: getDiffuseColorCorrection m.texmap_diffuse
				default: m.texmap_diffuse
			)
			
			showTextureMap m tex on
		)
	)
	
	on btnCheckIsolated pressed do
	(
		title = "Check Isolated Verts"
		checkErrors = 0
		
		for i in geometry do
		(
			theResults = #() 
			resultType = IsolatedVertices.Check currentTime i &theResults	
						
			if(theResults.count > 0) do checkErrors += theResults.count 
		)
		
		if(checkErrors > 0) then (
			m = "Found " + checkErrors as string + " isolated vertices!\nDo you want to fix it?"
			q = queryBox m title: title
			if(q) do (
				for o in geometry do
				(
					case (classOf o) of
					(
						Editable_Poly:
						(
							o.deleteIsoVerts()
							o.DeleteIsoMapVerts()
						)
						Editable_Mesh:
						(
							meshOp.deleteIsoVerts o
							meshOp.deleteIsoMapVertsAll o
						)
					)
				)
				
				messageBox "Success!" title: title
			)			
		) else (
			m = "Found " + checkErrors as string + " isolated vertices!"
			messageBox m title: title beep: false
		)				
	)
	
	on btnCheckSmoothGroups pressed do
	(		
		title = "Check Missing Smooth Groups"
		selObjects = #()
		
		for i in geometry do (					
			badSmGroups = #()
			o = i.baseobject
			
			faces = polyop.getNumFaces o
			for f in 1 to faces do (
				g = polyop.getFaceSmoothGroup o f
				if(g == 0) do append badSmGroups f
			)

			if(badSmGroups.count > 0) do (
				polyop.setFaceSelection o (badSmGroups as bitarray)	
				append selObjects i
			)
		)
		
		if(selObjects.count > 0) then (
			m = "Found " + selObjects.count as string + " objects with missing smooth groups!\nDo you want select these objects?"
			q = queryBox m title: title
			if(q) do (
				clearSelection()
				try(select selObjects) catch()
			)			
		) else (
			m = "Found 0 objects with missing smooth groups!"
			messageBox m title: title beep: false
		)
	)
	
	on btnCheckNonManifold pressed do
	(
		selObjects = #()
		title = "Check Non Manifold Polygons"
		
		for i in geometry do
		(
			face_sel = #{}			
			o = i.baseobject
			faces = polyop.getNumFaces o
			local isCheck = false
						
			for f in 1 to faces do (
				fv = polyop.getFaceDeg o f
				
				if(fv > 4) do (
					face_sel[f] = true
					polyop.setFaceSelection o face_sel
					isCheck = true
				)
			)
			
			if(isCheck == true) do append selObjects i
		)
		
		if(selObjects.count > 0) then (
			m = "Found " + selObjects.count as string + " objects with non manifold polys!\nDo you want fix these objects?"
			q = queryBox m title: title
			if(q) do (
				/*clearSelection()
				try(select selObjects) catch()*/
				undo "Turn To Poly" on (
					for i in selObjects do (
						turn = Turn_to_Poly()
						turn.limitPolySize = on
						turn.maxPolySize = 4
						addModifier i turn
						convertToPoly i
					)	
				)					
			)			
		) else (
			m = "Found 0 objects with non manifold polys!"
			messageBox m title: title beep: false
		)
	)
	
	on cbxToggleStatistics changed v do
	(
		showStatistics()
	)
	
	on _rQACheck open do
	(
		showStatistics()
	)
	
	on _rQACheck close do
	(
		unregisterRedrawViewsCallback gw_DrawTriangleCnt
		forceCompleteRedraw()
	)
)

rollout _rAbout "About" 
(
	label lblName "" 
	label lblVer "" 
	
	label lblAuthor "" height: 30
	label lblCopy ""  height: 30
	
	on _rAbout open do
	(		
		i = getScriptInfo (getThisScriptFilename())
			
		lblName.caption = i[1]
		lblAuthor.caption = i[2]
		lblVer.caption = i[3]
		lblCopy.caption = i[6]
	)
)

try(closeRolloutFloater rIKEAVRMODELQA) catch()
global rIKEAVRMODELQA = newRolloutFloater " IKEA VR Model QA" 220 360

addRollout _rQACheck rIKEAVRMODELQA rolledUp:false 
addRollout _rAbout rIKEAVRMODELQA rolledUp:true 