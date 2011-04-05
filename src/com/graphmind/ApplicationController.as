package com.graphmind {
  
	import com.graphmind.data.DrupalViews;
	import com.graphmind.event.EventCenter;
	import com.graphmind.event.EventCenterEvent;
	import com.graphmind.util.Log;
	import com.kitten.events.ConnectionEvent;
	import com.kitten.events.ConnectionIOErrorEvent;
	import com.kitten.events.ConnectionNetStatusEvent;
	
	import mx.core.Application;
	
	import plugins.*;
	
	
	/**
	 * Emitted events.
	 */
	[Event(name="applicationDataComplete", type="com.graphmind.event.ApplicationEvent")]
	public class ApplicationController {
	  
	  /**
	  * Shared instance.
	  */
	  [Bindable]
	  public static var i:ApplicationController;
	  
		/**
		 * Logging mode is enabled or not.
		 */
		public static var LOG_MODE:Boolean = true;
		
    /**
     * Tree map view controller.
     */
    [Bindable]
    public var treeMapViewController:TreeMapViewController;
    
    /**
    * Application form elemets' controller.
    */
    [Bindable]
    public var appFormController:AppFormController;
		
		/**
		 * Indicates the access permissions.
		 */
		protected var _isEditable:Boolean = false;
		
		/**
		 * Feature array.
		 */
		public var features:Array;

    
		/**
		 * Constructor.
		 */
		public function ApplicationController() {
		  ApplicationController.i = this;
		  
		  // Add general ui form controller
		  appFormController = new AppFormController();
		  
      // Edit mode has to be false by default.
      // Editing privileges have to be arrived from the backend with the user object.
      setEditMode(false);
      
      treeMapViewController = new TreeMapViewController();
      GraphMind.i.map.addChild(this.treeMapViewController.view);
      
		  // Establish connection to the Drupal site.
      ConnectionController.mainConnection = ConnectionController.createConnection(getBaseDrupalURL());
      ConnectionController.mainConnection.isSessionAuthentication = true;
      
      ConnectionController.mainConnection.addEventListener(ConnectionEvent.CONNECTION_IS_READY, onSuccess_siteIsConnected);
      ConnectionController.mainConnection.addEventListener(ConnectionIOErrorEvent.IO_ERROR_EVENT, ConnectionController.defaultIOErrorHandler);
      ConnectionController.mainConnection.addEventListener(ConnectionNetStatusEvent.NET_STATUS_EVENT, ConnectionController.defaultNetStatusHandler);
      ConnectionController.mainConnection.connect();
      
      EventCenter.subscribe(EventCenterEvent.REQUEST_FOR_FREEMIND_XML, onAppFormRequestForFreemindXml);
		}
			
			
		/**
		 * Get the host Drupal site's URL
		 */
		public static function getBaseDrupalURL():String {
			return Application.application.parameters.basePath;
		}
		
		
		/**
		 * Get hosting node's NID
		 */
		public static function getHostNodeID():int {
			return Application.application.parameters.nid;
		}
		
		
		/**
		 * URL for the icons.
		 */
		public static function getIconPath():String {
			return Application.application.parameters.iconDir;
		}


		/**
		 * Site is connected already
		 */
		protected function onSuccess_siteIsConnected(event:ConnectionEvent):void {
		  Log.info("Connection to Drupal is established.");
			// Get all the available features
			ConnectionController.mainConnection.call('graphmind.getFeatures', onSuccess_featuresAreLoaded, null, getHostNodeID());
			ConnectionController.mainConnection.call('graphmind.getViews', onSuccess_viewsListsAreLoaded, null);
			ConnectionController.mainConnection.call('node.get', onSuccess_rootNodeIsLoaded, null, getHostNodeID());
		}
		
		
		/**
		 * Features are loaded.
		 * Features are disabled by default.
		 */
		protected function onSuccess_featuresAreLoaded(result:Object):void {
		  Log.info("Features are loaded: " + result.toString());
		  this.features = result as Array;
		}
		
		
		/**
		 * Base site's views are loaded already
		 */
		protected function onSuccess_viewsListsAreLoaded(result:Object):void {
		  Log.info("Views lists are loaded: " + (result as Array).length);
		  // Populate Views lists.
      for each (var data:Object in result) {
        new DrupalViews(data, ConnectionController.mainConnection);
      }
		}

  
    /**
    * Root node is loaded.
    */
    protected function onSuccess_rootNodeIsLoaded(result:Object):void {
      Log.info("Root node is loaded: " + result.nid);
      setEditMode(result.graphmindEditable == '1');
      TreeMapViewController.rootNode = ImportManager.importNodesFromDrupalResponse(result);
      
      // Call map to draw its contents.
      EventCenter.notify(EventCenterEvent.MAP_UPDATED);
    }

    
    /**
    * Checks if the user has access to edit the mindmap.
    * @TODO if not, it should be only a not-savable mode, not an editless mode.
    */
		public function isEditable():Boolean {
			return _isEditable;
		}
		
		
		/**
		 * Set the edit mode.
		 */
		public function setEditMode(editable:Boolean):void {
			_isEditable = editable;
			if (!_isEditable) {
				GraphMind.i.currentState = 'only_view_mode';
			} else {
				GraphMind.i.currentState = '';
			}
		}
		
		
		/**
		 * Checks is the map is connected to a site.
		 */
		public function isBaseConnectionLive():Boolean {
		  return ConnectionController.mainConnection.isConnected;
		}
		
		
		protected function onAppFormRequestForFreemindXml(event:EventCenterEvent):void {
		  var xml:String = ExportController.getFreeMindXML(TreeMapViewController.rootNode);
		  (event.data as Function)(xml);
		}

	}

}
