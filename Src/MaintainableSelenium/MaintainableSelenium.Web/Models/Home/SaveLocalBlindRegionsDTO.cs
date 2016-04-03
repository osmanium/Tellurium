using System.Collections.Generic;
using MaintainableSelenium.Toolbox.Screenshots.Domain;

namespace MaintainableSelenium.Web.Models.Home
{
    public class SaveLocalBlindRegionsDTO
    {
        public long TestCaseId { get; set; }
        public long BrowserPatternId { get; set; }

        public List<BlindRegion> LocalBlindRegions { get; set; }

        public SaveLocalBlindRegionsDTO()
        {
            LocalBlindRegions = new List<BlindRegion>();
        }
    }
}