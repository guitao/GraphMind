/**
 * @Class StageManager
 * 
 * Intention: Provides a top level access to the UI and handles UI related tasks
 * 
 * Responsibilities:
 *  - give access to UI
 *  - manage UI changes
 *    - state changes
 *    - redraw stage
 */
package com.graphmind
{
	import com.graphmind.data.NodeItemData;
	import com.graphmind.data.ViewsCollection;
	import com.graphmind.data.ViewsList;
	import com.graphmind.display.NodeItem;
	import com.graphmind.net.SiteConnection;
	import com.graphmind.temp.TempItemLoadData;
	import com.graphmind.temp.TempViewLoadData;
	import com.graphmind.util.DesktopDragInfo;
	import com.graphmind.util.Log;
	
	import flash.display.Bitmap;
	import flash.display.BitmapData;
	import flash.display.MovieClip;
	import flash.display.StageDisplayState;
	import flash.events.MouseEvent;
	import flash.ui.ContextMenu;
	import flash.utils.clearTimeout;
	import flash.utils.setTimeout;
	
	import mx.collections.ArrayCollection;
	import mx.controls.Alert;
	import mx.controls.Image;
	import mx.core.Application;
	import mx.core.UIComponent;
	import mx.events.ListEvent;
	import mx.rpc.events.ResultEvent;
	
	public class StageManager
	{
		private static var _instance:StageManager = null;
		[Bindable]
		public static var DEFAULT_DESKTOP_HEIGHT:int = 2000;
		[Bindable]
		public static var DEFAULT_DESKTOP_WIDTH:int = 3000;
		
		// The stage object
		public var lastSelectedNode:NodeItem = null;
		public var baseNode:NodeItem = null;
		public var dragAndDrop_sourceNodeItem:NodeItem;
		public var isDragAndDrop:Boolean = false;
		public var isPrepairedDragAndDrop:Boolean = false;
		public var isDesktopDragged:Boolean = false;
		private var _desktopDragInfo:DesktopDragInfo = new DesktopDragInfo();
		[Bindable]
		private var _isChanged:Boolean = false;
		[Bindable]
		public var selectedNodeData:ArrayCollection = new ArrayCollection();
		
		private var previewBitmapData:BitmapData = new BitmapData(2880, 2000, true);
		private var previewBitmap:Bitmap = new Bitmap(previewBitmapData);
		private var previewTimer:uint;
		
		public static function getInstance():StageManager {
			if (_instance == null) {
				_instance = new StageManager();
			}
			
			return _instance;
		}
		
		/**
		 * Initialize stage.
		 */
		public function init():void {
			// Scroll mindmap canvas to center
			GraphMind.instance.mindmapCanvas.desktop_wrapper.verticalScrollPosition = (GraphMind.instance.mindmapCanvas.desktop.height - GraphMind.instance.mindmapCanvas.desktop_wrapper.height) / 2;
			
			// Node title RTE editor's default color
			GraphMind.instance.mindmapToolsPanel.node_info_panel.nodeLabelRTE.colorPicker.selectedColor = 0x555555;
			
			// Preview window init
			previewBitmap.width = 180;
			previewBitmap.height = 120;
			GraphMind.instance.mindmapCanvas.previewWindow.addChild(previewBitmap);
			
			// Remove base context menu items (not perfect, though)
			var cm:ContextMenu = new ContextMenu();
			cm.hideBuiltInItems();
			MovieClip(GraphMind.instance.systemManager).contextMenu = cm;
		}
		
		/**
		 * Load base node.
		 */
		public function loadBaseNode():void {
			ConnectionManager.getInstance().nodeLoad(
				GraphMindManager.getInstance().getHostNodeID(), 
				GraphMindManager.getInstance().baseSiteConnection, 
				_loadBaseNode_stage_node_loaded
			);
		}
		
		/**
		 * Load base node - stage 2.
		 */
		private function _loadBaseNode_stage_node_loaded(result:ResultEvent):void {
			GraphMindManager.getInstance().setEditMode(result.result.graphmindEditable == '1');
			
			// ! Removed original data object: result.result.
			// This caused a mailformed export string.
			var itemData:NodeItemData = new NodeItemData({}, NodeItemData.NODE, GraphMindManager.getInstance().baseSiteConnection);
			itemData.type = NodeItemData.NODE;
			itemData.title = result.result.title;
			var nodeItem:NodeItem = new NodeItem(itemData);
			
			// @WTF sometimes body_value is the right value, sometimes not
			var is_valid_mm_xml:Boolean = false;
			var body:String = result.result.body.toString();
			if (body.length > 0) {
				var xmlData:XML = new XML(body);
				var nodes:XML = xmlData.child('node')[0];
				is_valid_mm_xml = nodes !== null;
			}
				
			if (is_valid_mm_xml) {
				var importedBaseNode:NodeItem = ImportManager.getInstance().importMapFromString(baseNode, body);
				addChildToStage(importedBaseNode);
				baseNode = importedBaseNode;
			} else {
				addChildToStage(nodeItem);
				baseNode = nodeItem;
			}
			
			refreshNodePositions();
		}		
				
		public function onDataGridItemClick_baseState(event:ListEvent):void {
			if (event.itemRenderer.data is ViewsCollection) {
				(event.itemRenderer.data as ViewsCollection).handleDataGridSelection();
			} else {
				Log.warning('onDataGridItemClick_baseState event is not ViewsCollection.');
			}
		}
		
		/**
		 * Select a views from datagrid on the views load panel.
		 */
		public function onDataGridItemClick_loadViewState(event:ListEvent):void {
			Log.info('onDataGridItemClick_loadViewState');
			var selectedViewsCollection:ViewsCollection = event.itemRenderer.data as ViewsCollection;
			
			GraphMind.instance.panelLoadView.view_name.text = selectedViewsCollection.name;
		}
		
		/**
		 * Event handler for
		 */
		public function onConnectFormSubmit():void {
			var sc:SiteConnection = SiteConnection.createSiteConnection(
				GraphMind.instance.mindmapToolsPanel.node_connections_panel.connectFormURL.text,
				GraphMind.instance.mindmapToolsPanel.node_connections_panel.connectFormUsername.text,
				GraphMind.instance.mindmapToolsPanel.node_connections_panel.connectFormPassword.text
			);
			ConnectionManager.getInstance().connectToSite(sc);
		}
		
		/**
		 * Add new element to the editor canvas.
		 */
		public function addChildToStage(element:UIComponent):void {
			GraphMind.instance.mindmapCanvas.desktop.addChild(element);
			refreshNodePositions();
		}
		
		/**
		 * Event for clicking on the view load panel.
		 */
		public function onLoadViewSubmitClick(event:MouseEvent):void {
			//var viewsList:ViewsList = new ViewsList();
			var viewsData:ViewsList = new ViewsList();
			viewsData.args   	= GraphMind.instance.panelLoadView.view_arguments.text;
			// Fields are not supported in Services for D6
			// viewsData.fields 	= stage.view_fields.text;
			viewsData.limit     = parseInt(GraphMind.instance.panelLoadView.view_limit.text);
			viewsData.offset    = parseInt(GraphMind.instance.panelLoadView.view_offset.text);
			viewsData.view_name = GraphMind.instance.panelLoadView.view_name.text;
			viewsData.parent    = GraphMind.instance.panelLoadView.view_views_datagrid.selectedItem as ViewsCollection;
			
			var loaderData:TempViewLoadData = new TempViewLoadData();
			loaderData.viewsData = viewsData;
			loaderData.nodeItem = lastSelectedNode;
			loaderData.success  = onViewsItemsLoadSuccess;
			
			ConnectionManager.getInstance().viewListLoad(loaderData);
			
			GraphMind.instance.currentState = '';
		}
		
		/**
		 * Event on cancelling views load panel.
		 */
		public function onLoadViewCancelClick(event:MouseEvent):void {
			GraphMind.instance.currentState = '';
		}
		
		/**
		 * Event on submitting item loading panel.
		 */
		public function onLoadItemSubmitClick(event:MouseEvent):void {
			var nodeItemData:NodeItemData = new NodeItemData(
				{},
				GraphMind.instance.panelLoadDrupalItem.item_type.selectedItem.data,
				GraphMind.instance.panelLoadDrupalItem.item_source.selectedItem as SiteConnection
			);
			nodeItemData.drupalID = parseInt(GraphMind.instance.panelLoadDrupalItem.item_id.text);
			
			var loaderData:TempItemLoadData = new TempItemLoadData();
			loaderData.nodeItem = lastSelectedNode;
			loaderData.nodeItemData = nodeItemData;
			loaderData.success = onItemLoadSuccess;
			
			ConnectionManager.getInstance().itemLoad(loaderData);
			
			GraphMind.instance.currentState = '';
		}
		
		/**
		 * Event for on item loader cancel.
		 */
		public function onLoadItemCancelClick(event:MouseEvent):void {
			GraphMind.instance.currentState = '';
		}
		
		public function onViewsItemsLoadSuccess(list:Array, requestData:TempViewLoadData):void {
			if (list.length == 0) {
				Alert.show('Zero result.');
			}
			for each (var nodeData:Object in list) {
				// @TODO update or append checkbox for the panel?
				var similarNode:NodeItem = requestData.nodeItem.getEqualChild(nodeData, requestData.viewsData.parent.baseTable)
				if (similarNode) {
					similarNode.updateDrupalItem_result(nodeData, null);
					continue;
				}
				
				var nodeItemData:NodeItemData = new NodeItemData(
					nodeData, 
					requestData.viewsData.parent.baseTable, 
					requestData.viewsData.parent.source
				);
				var nodeItem:NodeItem = new NodeItem(nodeItemData);
				requestData.nodeItem.addNodeChild(nodeItem);
			}
		}
		
		// @TODO maybe it's not the right place for this, damn it
		// Suggested name: createNode(parent)
		public function onNewNormalNodeClick(parent:NodeItem):void {
			var nodeItemData:NodeItemData = new NodeItemData({}, NodeItemData.NORMAL, SiteConnection.createSiteConnection());
			var nodeItem:NodeItem = new NodeItem(nodeItemData);
			parent.addNodeChild(nodeItem);
			nodeItem.selectNode();
			
			// HOOK
			PluginManager.callHook(NodeItem.HOOK_NODE_CREATED, {node: nodeItem});
		}
		
		public function onItemLoadSuccess(result:Object, requestData:TempItemLoadData):void {
			requestData.nodeItemData.data = result;
			var nodeItem:NodeItem = new NodeItem(requestData.nodeItemData);
			requestData.nodeItem.addNodeChild(nodeItem);
			nodeItem.selectNode();
		}
		
		public function refreshNodePositions():void {
			if (!baseNode) return;
			baseNode.x = 0;
			baseNode.y = DEFAULT_DESKTOP_HEIGHT >> 1;
			baseNode.refreshChildNodePosition();
			refreshPreviewWindow();
		}
		
		public function onSaveClick():void {
			GraphMindManager.getInstance().save();
		}
		
		public function onDumpClick():void {
			GraphMind.instance.mindmapToolsPanel.node_save_panel.freemindExportTextarea.text = GraphMindManager.getInstance().exportToFreeMindFormat();
		}
		
		public function onExportClick():void {
			var mm:String = GraphMindManager.getInstance().exportToFreeMindFormat();
			Alert.show('Implement later');
		}
		
		public function onAddOrUpdateClick(event:MouseEvent):void {
			if (!lastSelectedNode) baseNode.selectNode();
			
			lastSelectedNode.data[GraphMind.instance.mindmapToolsPanel.node_attributes_panel.attributes_update_param.text] = GraphMind.instance.mindmapToolsPanel.node_attributes_panel.attributes_update_value.text;
			lastSelectedNode.selectNode();
			
			GraphMind.instance.mindmapToolsPanel.node_attributes_panel.attributes_update_param.text = GraphMind.instance.mindmapToolsPanel.node_attributes_panel.attributes_update_value.text = '';
		}
		
		public function onRemoveAttributeClick():void {
			if (!lastSelectedNode || GraphMind.instance.mindmapToolsPanel.node_attributes_panel.attributes_update_param.text.length == 0) return;
			
			lastSelectedNode.dataDelete(GraphMind.instance.mindmapToolsPanel.node_attributes_panel.attributes_update_param.text);
			lastSelectedNode.selectNode();
			
			GraphMind.instance.mindmapToolsPanel.node_attributes_panel.attributes_update_param.text = GraphMind.instance.mindmapToolsPanel.node_attributes_panel.attributes_update_value.text = '';
		}
		
		public function toggleFullScreen():void {
			try {
				
				switch (Application.application.stage.displayState) {
					case StageDisplayState.FULL_SCREEN:
						Application.application.stage.displayState = StageDisplayState.NORMAL;
						break;
					case StageDisplayState.NORMAL:
						Application.application.stage.displayState = StageDisplayState.FULL_SCREEN;
						break;
				}
			} catch (e:Error) {
				
			}
		}
		
		public function onDragAndDropImageMouseUp(event:MouseEvent):void {
			GraphMind.instance.dragAndDrop_shape.visible = false;
			GraphMind.instance.dragAndDrop_shape.x = -GraphMind.instance.dragAndDrop_shape.width;
			GraphMind.instance.dragAndDrop_shape.y = -GraphMind.instance.dragAndDrop_shape.height;
		}
		
		public function prepaireDragAndDrop():void {
			isPrepairedDragAndDrop = true;
		}
		
		public function openDragAndDrop(source:NodeItem):void {
			isPrepairedDragAndDrop = false;
			isDragAndDrop = true;
			StageManager.getInstance().dragAndDrop_sourceNodeItem = source;
			GraphMind.instance.dragAndDrop_shape.visible = true;
			GraphMind.instance.dragAndDrop_shape.x = GraphMind.instance.mouseX - GraphMind.instance.dragAndDrop_shape.width / 2;
			GraphMind.instance.dragAndDrop_shape.y = GraphMind.instance.mouseY - GraphMind.instance.dragAndDrop_shape.height / 2;
			GraphMind.instance.dragAndDrop_shape.startDrag(false);
		}
		
		public function closeDragAndDrop():void {
			isDragAndDrop = false;
			isPrepairedDragAndDrop = false;
			GraphMind.instance.dragAndDrop_shape.visible = false;
			dragAndDrop_sourceNodeItem = null;
		}
		
		public function onNodeLabelRTESave():void {
			if (!checkLastSelectedNodeIsExists()) return;
			
			lastSelectedNode.title = GraphMind.instance.mindmapToolsPanel.node_info_panel.nodeLabelRTE.htmlText;
		}
		
		public function onSaveLink():void {
			if (!checkLastSelectedNodeIsExists()) return;
			
			lastSelectedNode.link = GraphMind.instance.mindmapToolsPanel.node_info_panel.link.text;
		}
		
		public function checkLastSelectedNodeIsExists():Boolean {
			if (!lastSelectedNode) {
				Alert.show("Please, select a node first.", "Graphmind");
				return false;
			}
			
			return true;
		}
		
		public function onIconClick(event:MouseEvent):void {
			if (!checkLastSelectedNodeIsExists()) return;
			
			var source:String = (event.currentTarget as Image).source.toString();
			lastSelectedNode.addIcon(source);
			lastSelectedNode.refactorNodeBody();
			lastSelectedNode.refreshParentTree();
		}
		
		public function onDragDesktopStart():void {
			isDesktopDragged = true;
			_desktopDragInfo.oldVPos = GraphMind.instance.mindmapCanvas.desktop_wrapper.mouseY;
			_desktopDragInfo.oldHPos = GraphMind.instance.mindmapCanvas.desktop_wrapper.mouseX;
			_desktopDragInfo.oldScrollbarVPos = GraphMind.instance.mindmapCanvas.desktop_wrapper.verticalScrollPosition;
			_desktopDragInfo.oldScrollbarHPos = GraphMind.instance.mindmapCanvas.desktop_wrapper.horizontalScrollPosition;
		}
		
		public function onDragDesktop(event:MouseEvent):void {
			if (isDesktopDragged) {
				var deltaV:Number = GraphMind.instance.mindmapCanvas.desktop_wrapper.mouseY - _desktopDragInfo.oldVPos;
				var deltaH:Number = GraphMind.instance.mindmapCanvas.desktop_wrapper.mouseX - _desktopDragInfo.oldHPos;
				GraphMind.instance.mindmapCanvas.desktop_wrapper.verticalScrollPosition   = _desktopDragInfo.oldScrollbarVPos - deltaV;
				GraphMind.instance.mindmapCanvas.desktop_wrapper.horizontalScrollPosition = _desktopDragInfo.oldScrollbarHPos - deltaH;
			}
		}
		
		public function onToggleCloudClick():void {
			if (!checkLastSelectedNodeIsExists()) return;
			
			lastSelectedNode.toggleCloud(true);
		}
		
		public function refreshPreviewWindow():void {
			// Timeout can help on performance
			clearTimeout(previewTimer);
			previewTimer = setTimeout(function():void {
				previewBitmapData = new BitmapData(2880, 2000, false, 0x333333);
				previewBitmap.bitmapData = previewBitmapData;
				previewBitmapData.draw(GraphMind.instance.mindmapCanvas.desktop_cloud);
				previewBitmapData.draw(GraphMind.instance.mindmapCanvas.desktop);
				trace('refresh');
			}, 400);
		}
		
		public function set isChanged(changed:Boolean):void {
			_isChanged = changed;
		}
		
		[Bindable]
		public function get isChanged():Boolean {
			return _isChanged;
		}
	}
}
