namespace MaintainableSelenium.Toolbox.Screenshots
{
    public class TestResult: Entity
    {
        public virtual string ScreenshotName { get; set; }
        public virtual string BrowserName { get; set; }
        public virtual bool TestPassed { get; set; }
        public virtual BrowserPattern Pattern { get; set; }
        public virtual TestSession TestSession { get; set; }
        public virtual ScreenshotData ErrorScreenshot { get; set; }
    }
}