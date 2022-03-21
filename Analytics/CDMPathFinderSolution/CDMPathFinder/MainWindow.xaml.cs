using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Navigation;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace CDMPathFinder
{
    /// <summary>
    /// Interaction logic for MainWindow.xaml
    /// </summary>
    public partial class MainWindow : Window
    {
        public MainWindow()
        {
            InitializeComponent();
        }

        private void Button_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                if (string.IsNullOrEmpty(tbxConnectionString.Text) ||
               string.IsNullOrEmpty(tbxContainerName.Text) ||
               string.IsNullOrEmpty(tbxTablesMainPath.Text))
                {
                    tbxReturn.Text = "Mandatory data missing";
                }
                else
                {
                    Application.Current.Dispatcher.BeginInvoke(DispatcherPriority.Input,
                    new Action(() =>
                    {
                        CDMPathFinderClass manifestTraverser = new CDMPathFinderClass(tbxConnectionString.Text, tbxContainerName.Text, tbxTablesMainPath.Text);
                        tbxReturn.Text = manifestTraverser.GetAllTablesPath();
                    }));
                    tbxReturn.Text = "PROCESSING...";
                }
            }
            catch (Exception ex)
            {
                while (ex != null)
                {
                    tbxReturn.Text += ex.Message;
                    tbxReturn.Text += Environment.NewLine;
                    ex = ex.InnerException;

                }
            }
        }
    }
}
